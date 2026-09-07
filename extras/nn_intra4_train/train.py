#!/usr/bin/env python3
# Copyright 2026 Google Inc. All Rights Reserved.
#
# Use of this source code is governed by a BSD-style license
# that can be found in the COPYING file in the root of the source
# tree. An additional intellectual property rights grant can be found
# in the file PATENTS. All contributing project authors may
# be found in the AUTHORS file in the root of the source tree.
# -----------------------------------------------------------------------------
#
# Offline trainer for the intra4 mode-decision NN pruner (see
# src/enc/nn_intra4_enc.h/.c). Reads binary dumps produced by cwebp built
# with -DWEBP_NN_INTRA4_DUMP (WEBP_NN_DUMP_PATH env var), trains one small
# MLP per QP bucket, and emits src/enc/nn_intra4_weights.h.
#
# Usage:
#   pip install torch numpy
#   python3 train.py --dataset /path/to/dump1.bin /path/to/dump2.bin \
#       --output ../../src/enc/nn_intra4_weights.h
#
# Author: Skal (pascal.massimino@gmail.com)

import argparse
import copy
import struct

import numpy as np
import torch
import torch.nn as nn

# Must match src/dsp/nn_intra4_dims.h.
NN_INPUT_DIM = 49
NN_HIDDEN = 16
NUM_BMODES = 10
NN_SCALE_CTX = 16384
NN_SCALE_W = 4096
NN_SCALE_H1 = 1024
NN_SCALE_H2 = 512
NN_SHIFT_1 = 16
NN_SHIFT_2 = 13
RECORD_FMT = f'<ii{NN_INPUT_DIM}h'  # ctx is dumped as int16 (Q14), not float.
RECORD_SIZE = struct.calcsize(RECORD_FMT)

# Must match VP8NNIntra4PickWeights() in src/enc/nn_intra4_enc.c.
BUCKETS = [
    ('Low', lambda q: q < 30),
    ('Mid', lambda q: (q >= 30) & (q < 70)),
    ('High', lambda q: q >= 70),
]


RECORD_DTYPE = np.dtype([('quant', '<i4'), ('mode', '<i4'),
                         ('ctx', '<i2', (NN_INPUT_DIM,))])
assert RECORD_DTYPE.itemsize == RECORD_SIZE


def load_dataset(paths, max_samples=None):
  chunks = [np.fromfile(path, dtype=RECORD_DTYPE) for path in paths]
  records = np.concatenate(chunks) if len(chunks) > 1 else chunks[0]
  if max_samples is not None and len(records) > max_samples:
    rng = np.random.default_rng(0)
    idx = rng.choice(len(records), size=max_samples, replace=False)
    records = records[idx]
  # ctx was dumped as an exact int16 Q14 fixed-point value (see
  # src/enc/nn_intra4_enc.c); convert back to float for training.
  ctx_float = records['ctx'].astype(np.float32) / NN_SCALE_CTX
  return records['quant'].astype(np.int32), records['mode'].astype(
      np.int64), ctx_float


class MLP(nn.Module):

  def __init__(self):
    super().__init__()
    self.fc1 = nn.Linear(NN_INPUT_DIM, NN_HIDDEN)
    self.fc2 = nn.Linear(NN_HIDDEN, NN_HIDDEN)
    self.fc3 = nn.Linear(NN_HIDDEN, NUM_BMODES)

  def forward(self, x):
    x = torch.relu(self.fc1(x))
    x = torch.relu(self.fc2(x))
    return self.fc3(x)


def train_bucket(ctxs, modes, epochs, lr, batch_size=4096, val_frac=0.05,
                 test_ctxs=None, test_modes=None, eval_every=None):
  """Trains one QP-bucket model. If test_ctxs/test_modes (a held-out set,
  disjoint from ctxs/modes) are given, tracks and returns the checkpoint
  with the best top-4 recall on that set instead of just the final epoch --
  top-K recall vs. a genuinely disjoint set is a better proxy for
  deployed pruning safety than the loss-minimizing epoch on an in-sample
  split, and the two don't always coincide over long training runs."""
  n = len(modes)
  rng = np.random.default_rng(0)
  perm = rng.permutation(n)
  n_val = max(1, int(n * val_frac))
  val_idx, train_idx = perm[:n_val], perm[n_val:]

  x_all = torch.from_numpy(ctxs)
  y_all = torch.from_numpy(modes)
  x_train, y_train = x_all[train_idx], y_all[train_idx]
  x_val, y_val = x_all[val_idx], y_all[val_idx]

  track_best = test_ctxs is not None
  if eval_every is None:
    eval_every = max(1, epochs // 10)
  best_top4 = -1.0
  best_state = None
  best_epoch = -1

  model = MLP()
  opt = torch.optim.Adam(model.parameters(), lr=lr)
  sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)
  # DC alone is ~65% of samples (it's the fallback for flat/ambiguous
  # blocks), so plain cross-entropy lets the net minimize loss by defaulting
  # to DC whenever unsure -- exactly the failure mode observed in practice
  # (rarer, mostly directional modes getting pruned out and misrouted to
  # DC). Full inverse-frequency class weighting overcorrects (DC's own
  # recall collapses, which dominates the aggregate top-K recall that
  # actually matters for pruning safety); sqrt-scaled inverse frequency is
  # the softer compromise that fixes the misrouting without that cost.
  counts = torch.bincount(y_train, minlength=NUM_BMODES).float().clamp(min=1)
  inv_freq = counts.sum() / (NUM_BMODES * counts)
  class_weight = inv_freq.sqrt()
  loss_fn = nn.CrossEntropyLoss(weight=class_weight)

  steps_per_epoch = max(1, len(train_idx) // batch_size)
  for epoch in range(epochs):
    shuffle = rng.permutation(len(train_idx))
    total_loss = 0.0
    for s in range(steps_per_epoch):
      idx = shuffle[s * batch_size:(s + 1) * batch_size]
      opt.zero_grad()
      loss = loss_fn(model(x_train[idx]), y_train[idx])
      loss.backward()
      opt.step()
      total_loss += loss.item()
    sched.step()
    if epoch % eval_every == 0 or epoch == epochs - 1:
      with torch.no_grad():
        val_acc = (model(x_val).argmax(dim=1) == y_val).float().mean().item()
      msg = (f'  epoch {epoch:4d}: loss={total_loss / steps_per_epoch:.4f} '
             f'val_acc={val_acc:.4f} lr={sched.get_last_lr()[0]:.2e}')
      if track_best:
        _, test_top4 = quantized_accuracy(model, test_ctxs, test_modes)
        msg += f' held_out_top4={test_top4:.4f}'
        if test_top4 > best_top4:
          best_top4 = test_top4
          best_state = copy.deepcopy(model.state_dict())
          best_epoch = epoch
          msg += '  <- best so far'
      print(msg)

  if track_best:
    print(f'  best epoch: {best_epoch} (held_out_top4={best_top4:.4f})')
    model.load_state_dict(best_state)
  return model


def format_array(values, shape):
  """Formats a flat list of ints as a nested C initializer matching 'shape'
  (e.g. [16, 49] -> "{{...}, {...}, ...}")."""
  if len(shape) == 1:
    return '{' + ', '.join(str(int(v)) for v in values) + '}'
  stride = 1
  for s in shape[1:]:
    stride *= s
  rows = [
      format_array(values[i * stride:(i + 1) * stride], shape[1:])
      for i in range(shape[0])
  ]
  return '{' + ', '.join(rows) + '}'


def quantize_weights(w, scale):
  q = np.round(w * scale)
  clipped = np.clip(q, -32768, 32767)
  n_clipped = np.count_nonzero(clipped != q)
  if n_clipped:
    print(f'  warning: {n_clipped} weight(s) clipped to int16 range')
  return clipped.astype(np.int64)


def model_to_c_struct(model, name):
  p = {k: v.detach().numpy().astype(np.float64) for k, v in
       model.state_dict().items()}
  w1q = quantize_weights(p['fc1.weight'], NN_SCALE_W)
  w2q = quantize_weights(p['fc2.weight'], NN_SCALE_W)
  w3q = quantize_weights(p['fc3.weight'], NN_SCALE_W)
  # Biases are pre-scaled to each layer's raw accumulator units (see
  # src/dsp/nn_intra4_dims.h) so they add directly into the int32 sum;
  # stored as int32, no clipping needed in practice (see max|score| check
  # in the trainer's accuracy report).
  b1q = np.round(p['fc1.bias'] * NN_SCALE_W * NN_SCALE_CTX).astype(np.int64)
  b2q = np.round(p['fc2.bias'] * NN_SCALE_W * NN_SCALE_H1).astype(np.int64)
  b3q = np.round(p['fc3.bias'] * NN_SCALE_W * NN_SCALE_H2).astype(np.int64)

  lines = [f'static const VP8NNIntra4WeightsQ {name} = {{']
  lines.append(f'  {format_array(w1q.flatten(), [NN_HIDDEN, NN_INPUT_DIM])},')
  lines.append(f'  {format_array(b1q, [NN_HIDDEN])},')
  lines.append(f'  {format_array(w2q.flatten(), [NN_HIDDEN, NN_HIDDEN])},')
  lines.append(f'  {format_array(b2q, [NN_HIDDEN])},')
  lines.append(f'  {format_array(w3q.flatten(), [NUM_BMODES, NN_HIDDEN])},')
  lines.append(f'  {format_array(b3q, [NUM_BMODES])}')
  lines.append('};')
  return '\n'.join(lines)


def quantized_accuracy(model, ctxs, modes):
  """Simulates the exact integer forward pass (matching src/dsp/enc.c's
  NNIntra4Score_C) to report the REAL post-quantization accuracy, not just
  the float model's."""
  p = {k: v.detach().numpy().astype(np.float64) for k, v in
       model.state_dict().items()}
  w1q = quantize_weights(p['fc1.weight'], NN_SCALE_W)
  w2q = quantize_weights(p['fc2.weight'], NN_SCALE_W)
  w3q = quantize_weights(p['fc3.weight'], NN_SCALE_W)
  b1q = np.round(p['fc1.bias'] * NN_SCALE_W * NN_SCALE_CTX).astype(np.int64)
  b2q = np.round(p['fc2.bias'] * NN_SCALE_W * NN_SCALE_H1).astype(np.int64)
  b3q = np.round(p['fc3.bias'] * NN_SCALE_W * NN_SCALE_H2).astype(np.int64)

  ctx_i = np.clip(np.round(ctxs * NN_SCALE_CTX), -32768, 32767).astype(
      np.int64)

  def rescale_relu(raw, shift):
    return np.clip((raw + (1 << (shift - 1))) >> shift, 0, 32767)

  raw1 = ctx_i @ w1q.T + b1q
  h1 = rescale_relu(raw1, NN_SHIFT_1)
  raw2 = h1 @ w2q.T + b2q
  h2 = rescale_relu(raw2, NN_SHIFT_2)
  scores = h2 @ w3q.T + b3q
  top1 = (scores.argmax(axis=1) == modes).mean()
  order = np.argsort(-scores, axis=1)
  top4 = (order[:, :4] == modes[:, None]).any(axis=1).mean()
  return top1, top4


HEADER_TEMPLATE = '''\
// Copyright 2026 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
//   Weights for the VP8NNIntra4WeightsQ MLP (see
//   src/dsp/nn_intra4_dims.h for the fixed-point layout), one table per
//   QP bucket (low/mid/high, see VP8NNIntra4PickWeights()).
//
//   Generated by extras/nn_intra4_train/train.py; do not hand-edit -- rerun
//   the trainer instead.
//
// Author: Skal (pascal.massimino@gmail.com)

#ifndef WEBP_ENC_NN_INTRA4_WEIGHTS_H_
#define WEBP_ENC_NN_INTRA4_WEIGHTS_H_

#include "src/dsp/nn_intra4_dims.h"

{bodies}

#endif  // WEBP_ENC_NN_INTRA4_WEIGHTS_H_
'''


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--dataset', nargs='+', required=True)
  parser.add_argument('--output', required=True)
  parser.add_argument(
      '--epochs', type=int, default=40,
      help='passes over the training set (each pass is many minibatch steps)')
  parser.add_argument('--lr', type=float, default=2e-3)
  parser.add_argument('--batch-size', type=int, default=4096)
  parser.add_argument(
      '--max-samples', type=int, default=None,
      help='randomly subsample the dataset to at most this many records')
  parser.add_argument(
      '--test-dataset', nargs='+', default=None,
      help='disjoint held-out dump(s) (e.g. from a separate set of images). '
           'When given, the best checkpoint per bucket is selected by top-4 '
           'recall on this set instead of just training to the final '
           'epoch -- recommended for long runs, since the loss-minimizing '
           'epoch on an in-sample split and the best epoch on genuinely '
           'unseen data don\'t always coincide.')
  parser.add_argument(
      '--eval-every', type=int, default=None,
      help='epochs between held-out evaluations (default: epochs//10)')
  args = parser.parse_args()

  quants, modes, ctxs = load_dataset(args.dataset, args.max_samples)
  print(f'loaded {len(modes)} samples from {len(args.dataset)} file(s)')

  test_quants = test_modes = test_ctxs = None
  if args.test_dataset:
    test_quants, test_modes, test_ctxs = load_dataset(args.test_dataset)
    print(f'loaded {len(test_modes)} held-out samples from '
          f'{len(args.test_dataset)} file(s)')

  bodies = []
  for name, pred in BUCKETS:
    mask = pred(quants)
    print(f'bucket {name}: {mask.sum()} samples')
    bucket_test_ctxs = bucket_test_modes = None
    if test_ctxs is not None:
      test_mask = pred(test_quants)
      bucket_test_ctxs = test_ctxs[test_mask]
      bucket_test_modes = test_modes[test_mask]
    model = train_bucket(ctxs[mask], modes[mask], args.epochs, args.lr,
                          batch_size=args.batch_size,
                          test_ctxs=bucket_test_ctxs,
                          test_modes=bucket_test_modes,
                          eval_every=args.eval_every)
    q_top1, q_top4 = quantized_accuracy(model, ctxs[mask], modes[mask])
    print(f'  quantized (int16/int32) top-1={q_top1:.4f} '
          f'top-4-recall={q_top4:.4f} on full bucket')
    bodies.append(model_to_c_struct(model, f'kNNIntra4Weights{name}'))

  with open(args.output, 'w') as f:
    f.write(HEADER_TEMPLATE.format(bodies='\n\n'.join(bodies)))
  print(f'wrote {args.output}')


if __name__ == '__main__':
  main()
