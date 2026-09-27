// Copyright 2026 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
//  Dimensions and 8-bit fixed-point layout of the intra4 mode-ranking
//  MLP (enabled by WEBP_NN_INTRA4_MLP): a small pixel-context MLP, using only
//  the depth-0 neighbours (29 inputs), with 8-bit weights and activations,
//  all-integer and SIMD-friendly.
//
//  Fixed-point layout:
//  * ctx[NN_INPUT_PAD]: int8 = (pixel - 128), i.e. real value * 128. The
//    last NN_INPUT_PAD - NN_INPUT_DIM entries are zero.
//  * w1/w2/w3: int8, per-output-channel scale. Rows are NN_INPUT_PAD long
//    (the padding weights are zero).
//  * b1/b2/b3: int32, in the dot-product's accumulator scale.
//  * hidden activations h1/h2: int8 in [0, 127] (post-ReLU).
//  * Requantization of a raw int32 accumulator (see NNRequant()): the
//    accumulator is first rounded down by NN_ACC_SHIFT bits (and saturated
//    to int16), then multiplied by a per-channel int16 multiplier m[], and
//    finally shifted down (with rounding) by a per-layer shift[].
//    Hidden layers are then clamped to [0, 127] (ReLU + saturation), and the
//    output logits are left as is.
//  * scores[NUM_BMODES]: int32 logits, in units of 1 / NN_LOGIT_SCALE.
//
//  Everything is exact integer arithmetic, so the C, SSE2 and NEON
//  implementations return bit-identical results.
//
// Author: Skal (pascal.massimino@gmail.com)

#ifndef WEBP_DSP_NN_INTRA4_DIMS_H_
#define WEBP_DSP_NN_INTRA4_DIMS_H_

#include <stdint.h>

#include "src/dec/common_dec.h"  // for NUM_BMODES
#include "src/webp/types.h"      // for WEBP_INLINE

// Base pixel context, shared by the Intra4 MLP ranker and the Intra16/
// Intra4 decision NN below: 29 int8 values, padded to NN_INPUT_PAD.
#define NN_INPUT_DIM 29
#define NN_HIDDEN 32

#define NN_INPUT_PAD 32    // input rows are padded to this length
#define NN_ACC_SHIFT 4     // accumulator pre-shift (see above)
#define NN_ACT_MAX 127     // hidden activations are in [0, NN_ACT_MAX]
#define NN_LOGIT_SCALE 32  // scores are logits * NN_LOGIT_SCALE

#ifdef WEBP_NN_INTRA4_MLP
// Context layout (all "depth 0": the reconstructed neighbours, except for the
// source block X). Sums to NN_INPUT_DIM.
#define NN_BLOCK 16    // X: source 4x4 block
#define NN_TOP 4       // T0: reconstructed row above
#define NN_TOPRIGHT 4  // R0: reconstructed row above-right
#define NN_LEFT 4      // L0: reconstructed column to the left
#define NN_CORNER 1    // C: reconstructed top-left pixel

#define NN_OUT_PAD 12  // number of (padded) outputs of the last layer

typedef struct {
  int8_t w1[NN_HIDDEN][NN_INPUT_PAD];
  int32_t b1[NN_HIDDEN];
  int16_t m1[NN_HIDDEN];
  int8_t w2[NN_HIDDEN][NN_HIDDEN];
  int32_t b2[NN_HIDDEN];
  int16_t m2[NN_HIDDEN];
  int8_t w3[NN_OUT_PAD][NN_HIDDEN];  // rows >= NUM_BMODES are zero
  int32_t b3[NN_OUT_PAD];
  int16_t m3[NN_OUT_PAD];
  int32_t shift[3];  // per-layer final down-shift (>= 1)
} VP8NNIntra4WeightsQ;
#endif  // WEBP_NN_INTRA4_MLP

// Macroblock type decision NN (Intra16 / Intra4): same arithmetic, but
// a smaller second hidden layer, and 3 outputs (padded to NNI16_OUT_PAD).
// The last layer's rows are padded to NN_INPUT_PAD (zero weights) so that the
// same dot-product kernels apply.
#define NNI16_H1 32
#define NNI16_H2 16
#define NNI16_OUT_PAD 4

typedef struct {
  int8_t w1[NNI16_H1][NN_INPUT_PAD];
  int32_t b1[NNI16_H1];
  int16_t m1[NNI16_H1];
  int8_t w2[NNI16_H2][NNI16_H1];
  int32_t b2[NNI16_H2];
  int16_t m2[NNI16_H2];
  int8_t w3[NNI16_OUT_PAD][NN_INPUT_PAD];  // last row and cols >= H2 are 0
  int32_t b3[NNI16_OUT_PAD];
  int16_t m3[NNI16_OUT_PAD];
  int32_t shift[3];
} VP8NNI16WeightsQ;

// Requantizes a raw int32 accumulator: see the description above.
static WEBP_INLINE int32_t NNRequant(int32_t acc, int32_t mult, int shift) {
  int32_t a = (acc + (1 << (NN_ACC_SHIFT - 1))) >> NN_ACC_SHIFT;
  a = (a < -32768) ? -32768 : (a > 32767) ? 32767 : a;
  return (a * mult + (1 << (shift - 1))) >> shift;
}

// Same, saturated to int16 (final logits).
static WEBP_INLINE int32_t NNRequantLogit(int32_t acc, int32_t mult,
                                          int shift) {
  const int32_t v = NNRequant(acc, mult, shift);
  return (v < -32768) ? -32768 : (v > 32767) ? 32767 : v;
}

// Same as NNRequant(), followed by ReLU and saturation to [0, NN_ACT_MAX].
static WEBP_INLINE int8_t NNRequantReLU(int32_t acc, int32_t mult, int shift) {
  const int32_t v = NNRequant(acc, mult, shift);
  return (v <= 0) ? 0 : (v > NN_ACT_MAX) ? NN_ACT_MAX : (int8_t)v;
}

#endif  // WEBP_DSP_NN_INTRA4_DIMS_H_
