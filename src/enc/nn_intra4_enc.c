// Copyright 2026 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Author: Skal (pascal.massimino@gmail.com)

#include "src/enc/nn_intra4_enc.h"

#include <string.h>  // for memcpy

#include "src/dsp/dsp.h"  // for BPS
#include "src/enc/nn_intra4_weights.h"

// Centers the Pixel values [-1, 1] inputs as 14bit fixed-point input.
static int16_t NNPixelQ(uint8_t v) {
  return (int16_t)(((int)v - 128) * (NN_SCALE_CTX / 128));
}

void VP8NNIntra4GatherContext(const VP8EncIterator* WEBP_RESTRICT const it,
                              int16_t ctx[NN_INPUT_DIM]) {
  const uint8_t* const blk = it->yuv_in + Y_OFF_ENC + VP8Scan[it->i4];
  const uint8_t* const top = it->i4_top;
  const int by4 = it->i4 >> 2;  // subblock row (0..3) within the macroblock
  const int bx4 = it->i4 & 3;   // subblock column (0..3) within the macroblock
  const int top_available = (by4 > 0);   // rows above resident in yuv_in?
  const int left_available = (bx4 > 0);  // columns left resident in yuv_in?
  int16_t* dst = ctx;
  int depth, i;

  // the source luma block
  for (i = 0; i < NN_BLOCK; ++i) {
    dst[i] = NNPixelQ(blk[(i >> 2) * BPS + (i & 3)]);
  }
  dst += NN_BLOCK;

  // depth 0: top border reconstructed samples.
  // depth 1..3 is the source samples above, or a copy of depth 0 if
  // unavailable.
  for (i = 0; i < 4; ++i) dst[i] = NNPixelQ(top[i]);
  if (top_available) {
    for (depth = 1; depth < 4; ++depth) {
      for (i = 0; i < 4; ++i) {
        dst[depth * 4 + i] = NNPixelQ(blk[i - depth * BPS]);
      }
    }
  } else {
    for (depth = 1; depth < 4; ++depth) {
      memcpy(&dst[depth * 4], dst, 4 * sizeof(dst[0]));  // replicate depth 0
    }
  }
  dst += NN_TOP;

  // Same, for left blocks. The reconstructed left column is
  // stored as top[-2-i] for row i=0 (nearest the top-left corner) to i=3
  // (bottom row).
  for (i = 0; i < 4; ++i) dst[i] = NNPixelQ(top[-2 - i]);
  if (left_available) {
    for (depth = 1; depth < 4; ++depth) {
      for (i = 0; i < 4; ++i) {
        dst[depth * 4 + i] = NNPixelQ(blk[i * BPS - depth]);
      }
    }
  } else {
    for (depth = 1; depth < 4; ++depth) {
      memcpy(&dst[depth * 4], dst, 4 * sizeof(dst[0]));  // replicate depth 0
    }
  }
  dst += NN_LEFT;

  dst[0] = NNPixelQ(top[-1]);
}

// QP-bucket thresholds. Splitting the QP-range in 3 segments, each with
// their model. Must match the training set and related weight computation.
#define NN_QP_LOW_MAX 30  // quant < this -> Low
#define NN_QP_MID_MAX 70  // quant < this -> Mid, else High

// TODO(skal): have a different model based on source image content and type?
const VP8NNIntra4WeightsQ* VP8NNIntra4PickWeights(int quant) {
  if (quant < NN_QP_LOW_MAX) return &kNNIntra4WeightsLow;
  if (quant < NN_QP_MID_MAX) return &kNNIntra4WeightsMid;
  return &kNNIntra4WeightsHigh;
}
