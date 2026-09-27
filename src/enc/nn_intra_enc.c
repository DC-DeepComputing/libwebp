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

#include "src/enc/nn_intra_enc.h"

#include <stdlib.h>  // for abs()

#include "src/dsp/dsp.h"  // for BPS
#include "src/enc/nn_i16_weights.h"
#include "src/enc/nn_proxy_weights.h"

// QP-bucket thresholds. Splitting the QP-range in 3 segments, each with
// their model. Must match the training set and related weight computation.
#define NN_QP_LOW_MAX 30  // quant < this -> Low
#define NN_QP_MID_MAX 70  // quant < this -> Mid, else High

#ifdef WEBP_NN_INTRA4_MLP

#include "src/enc/nn_intra4_weights.h"

static int8_t NNPixel(uint8_t v) { return (int8_t)((int)v - 128); }

void VP8NNIntra4GatherContext(const VP8EncIterator* WEBP_RESTRICT const it,
                              int8_t ctx[NN_INPUT_PAD]) {
  const uint8_t* const blk = it->yuv_in + Y_OFF_ENC + VP8Scan[it->i4];
  const uint8_t* const top = it->i4_top;
  int8_t* dst = ctx;
  int i;
  for (i = 0; i < NN_BLOCK; ++i) {
    dst[i] = NNPixel(blk[(i >> 2) * BPS + (i & 3)]);
  }
  dst += NN_BLOCK;
  for (i = 0; i < 4; ++i) dst[i] = NNPixel(top[i]);  // top
  dst += NN_TOP;
  for (i = 0; i < 4; ++i) dst[i] = NNPixel(top[4 + i]);  // top-right
  dst += NN_TOPRIGHT;
  for (i = 0; i < 4; ++i) dst[i] = NNPixel(top[-2 - i]);  // left
  dst += NN_LEFT;
  dst[0] = NNPixel(top[-1]);                                 // corner
  for (i = NN_INPUT_DIM; i < NN_INPUT_PAD; ++i) ctx[i] = 0;  // padding
}

const VP8NNIntra4WeightsQ* VP8NNIntra4PickWeights(int quant) {
  if (quant < NN_QP_LOW_MAX) return &kNNIntra4WeightsLow;
  if (quant < NN_QP_MID_MAX) return &kNNIntra4WeightsMid;
  return &kNNIntra4WeightsHigh;
}

#endif  // WEBP_NN_INTRA4_MLP

//------------------------------------------------------------------------------
// Macroblock-level luma decision

// 8 * log2(1 + g), as a piecewise-linear approximation, capped to 127.
static int Log8(int g) {
  const uint32_t v = (uint32_t)g + 1;
  int b = 0;
  while ((v >> (b + 1)) != 0) ++b;  // b = floor(log2(v))
  {
    const int r = 8 * b + (int)(((v << 3) >> b) & 7);
    return (r > 127) ? 127 : r;
  }
}

// Context layout (int8):
//   [0]      quant - 64
//   [1..16]  means of the 16 4x4 blocks of the source (row-major) - 128
//   [17..20] means of the 4 groups of 4 samples of the top border - 128
//   [21..24] same, for the left border
//   [25]     top-left sample - 128
//   [26,27]  log-energy of the horizontal / vertical gradient of the source
//            (minus 64)
//   [28]     64 if the source is flat, 0 otherwise
//   [29..31] zero padding

// Measured time (in 1/100 us) of each policy, out of a typical ~16 us
// macroblock: DC only, Intra16, Intra4 (DC-bound), exhaustive.
static const int kPolicyTime_cus[4] = {45, 170, 485, 610};
#define NN_I16_TOTAL_TIME_CUS 1600

void VP8NNI16ComputeBias(int mu_milli, int32_t bias[4]) {
  int i;
  for (i = 0; i < 4; ++i) {
    // mu * time / total, in NN_I16_LOG_SCALE units (rounded).
    const int64_t num =
        (int64_t)mu_milli * kPolicyTime_cus[i] * NN_I16_LOG_SCALE;
    const int64_t half = (int64_t)500 * NN_I16_TOTAL_TIME_CUS;
    const int64_t denom = (int64_t)1000 * NN_I16_TOTAL_TIME_CUS;
    bias[i] = (int32_t)((num >= 0 ? num + half : num - half) / denom);
  }
}

VP8NNI16PolicyType VP8NNI16Policy(const VP8EncIterator* WEBP_RESTRICT const it,
                                  int quant, int is_flat,
                                  const int32_t bias[4]) {
  int8_t ctx[NN_INPUT_PAD];
  int32_t scores[NNI16_OUT_PAD];
  const uint8_t* const src = it->yuv_in + Y_OFF_ENC;
  int x, y, i, gx = 0, gy = 0, policy = 0;

  ctx[0] = (int8_t)(quant - 64);
  for (i = 0; i < 16; ++i) {
    const uint8_t* const p = src + (i >> 2) * 4 * BPS + (i & 3) * 4;
    int sum = 0;
    for (y = 0; y < 4; ++y) {
      for (x = 0; x < 4; ++x) sum += p[y * BPS + x];
    }
    ctx[1 + i] = (int8_t)(((sum + 8) >> 4) - 128);
  }
  for (i = 0; i < 4; ++i) {
    const uint8_t* const t = it->y_top + 4 * i;
    const uint8_t* const l = it->y_left + 4 * i;
    ctx[17 + i] = (int8_t)(((t[0] + t[1] + t[2] + t[3] + 2) >> 2) - 128);
    ctx[21 + i] = (int8_t)(((l[0] + l[1] + l[2] + l[3] + 2) >> 2) - 128);
  }
  ctx[25] = (int8_t)(it->y_left[-1] - 128);
  for (y = 0; y < 16; ++y) {
    for (x = 0; x < 16; ++x) {
      const int v = src[y * BPS + x];
      if (x < 15) gx += abs(src[y * BPS + x + 1] - v);
      if (y < 15) gy += abs(src[(y + 1) * BPS + x] - v);
    }
  }
  ctx[26] = (int8_t)(Log8(gx) - 64);
  ctx[27] = (int8_t)(Log8(gy) - 64);
  ctx[28] = (int8_t)(is_flat ? 64 : 0);
  for (i = NN_INPUT_DIM; i < NN_INPUT_PAD; ++i) ctx[i] = 0;

  // scores[DC..I4]: predicted regrets (NN_I16_POLICY_ALL, exhaustive, has
  // none: 0). Pick the policy with the smallest regret + bias.
  VP8NNI16Score(&kNNIntra16Weights, ctx, scores);
  {
    int32_t best = scores[NN_I16_POLICY_DC] + bias[NN_I16_POLICY_DC];
    for (i = NN_I16_POLICY_I16; i <= NN_I16_POLICY_ALL; ++i) {
      const int32_t c = ((i < NN_I16_POLICY_ALL) ? scores[i] : 0) + bias[i];
      if (c < best) {
        best = c;
        policy = i;
      }
    }
  }
  return (VP8NNI16PolicyType)policy;
}

//------------------------------------------------------------------------------
// Intra4 linear "proxy" ranker

void ProxyRank(const uint8_t* WEBP_RESTRICT src,
               const uint8_t* WEBP_RESTRICT preds,
               const uint16_t* WEBP_RESTRICT mode_costs, int lambda, int quant,
               int32_t logits[NUM_BMODES]) {
  int64_t p[NUM_BMODES], pmin = INT64_MAX, r;
  int32_t x[21];
  int hmin = 65535, m, j;
  for (m = 0; m < NUM_BMODES; ++m) {
    p[m] = VP8SSE4x4(src, preds + VP8I4ModeOffsets[m]) +
           (((int64_t)2 * lambda * mode_costs[m]) >> 8);
    if (p[m] < pmin) pmin = p[m];
    if (mode_costs[m] < hmin) hmin = mode_costs[m];
  }
  r = ((int64_t)1 << 32) / (pmin + 32);  // one division per block
  x[0] = (quant - 64) * 64;
  for (m = 0; m < NUM_BMODES; ++m) {
    const int64_t dp = ((p[m] - pmin) * r) >> 23;
    const int dh = mode_costs[m] - hmin;
    x[1 + m] = (dp > 4096) ? 4096 : (int32_t)dp;
    x[11 + m] = (dh > 4096) ? 4096 : dh;
  }
  for (m = 0; m < NUM_BMODES; ++m) {
    int64_t acc = kNNProxyBias[m];
    for (j = 0; j < 21; ++j) acc += (int64_t)kNNProxyWeights[m][j] * x[j];
    logits[m] = (int32_t)(acc >> NN_PROXY_ACC_SHIFT);
  }
}
