// Copyright 2026 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
//  Dimensions and fixed-point layout of the intra4 mode-ranking MLP:
//
//  * Fixed-point layout (all-integer, for bit-exact inference)
//  * ctx[NN_INPUT_DIM] input: int16, 14-bit fixed-point (cf. NN_SCALE_CTX)
//  * w1/w2/w3 weights: int16, 12-bit fixed point (cf. NN_SCALE_W)
//  * b1/b2/b3 biases: int32 pre-scaled to dot-product's output range
//    (NN_SCALE_W*NN_SCALE_CTX for b1, NN_SCALE_W*NN_SCALE_H1 for b2,
//     NN_SCALE_W*NN_SCALE_H2 for b3).
//  * h1/h2 hidden activations are int16: the raw int32 dot-product
//    is down-scaled to NN_SCALE_H1/H2 using round-to-nearest-shift
//    (NN_SHIFT_1, NN_SHIFT_2), and then ReLU'd and saturated to int16.
//  * scores[NUM_BMODES] output are left as int32 (NN_SCALE_W*NN_SCALE_H2)
//
//  Scales were picked from the *observed* activation range on real
//  training data with a little headroom left.
//
// Author: Skal (pascal.massimino@gmail.com)

#ifndef WEBP_DSP_NN_INTRA4_DIMS_H_
#define WEBP_DSP_NN_INTRA4_DIMS_H_

#include <stdint.h>

#include "src/dec/common_dec.h"  // for NUM_BMODES
#include "src/webp/types.h"      // for WEBP_INLINE

// Context layout, around the current 4x4 subblock 'X' to be coded.
//
//         -2 -1 | 0  1  2  3 | 4  5  6  7
//         ------+------------+------------
// row -4:       |            | R3 R3 R3 R3
// row -3:       |            | R2 R2 R2 R2
// row -2:       | T1 T1 T1 T1| R1 R1 R1 R1
// row -1:     C | T0 T0 T0 T0| R0 R0 R0 R0
//         ------+------------+------------
// row  0:  L1 L0| X  X  X  X |
// row  1:  L1 L0| X  X  X  X |
// row  2:  L1 L0| X  X  X  X |
// row  3:  L1 L0| X  X  X  X |
//
// X        = NN_BLOCK:     source (4x4 px)
// T0/T1    = NN_TOP:       T0=reconstructed, T1=source (2x4 px)
// R0..R3   = NN_TOPRIGHT:  R0=reconstructed, R1..R3=source (4x4 px)
// L0/L1    = NN_LEFT:      L0=reconstructed, L1=source (2x4 px)
// C        = NN_CORNER:    top-left reconstructed pixel (1 px)
//
// * T1, R1-R3, L1 are source, unavailable to the decoder. Cheap for the
//   encoder.
// * LD_PRED/VL_PRED read the top-right neighbor directly, so NN_TOPRIGHT
//   is well-used budget.
// * Conversely, this other modes don't benefit much from wider bands. So
//   just stick to using 2px.
#define NN_BLOCK 16
#define NN_TOP 8
#define NN_TOPRIGHT 16
#define NN_LEFT 8
#define NN_CORNER 1
#define NN_INPUT_DIM (NN_BLOCK + NN_TOP + NN_TOPRIGHT + NN_LEFT + NN_CORNER)
#define NN_HIDDEN 16

#define NN_SCALE_CTX 16384  // 2^14
#define NN_SCALE_W 4096     // 2^12
#define NN_SCALE_H1 1024    // 2^10
#define NN_SCALE_H2 512     // 2^9
#define NN_SHIFT_1 16
#define NN_SHIFT_2 13

// Fixed-shape 2-hidden-layer MLP, quantized to 16b.
typedef struct {
  int16_t w1[NN_HIDDEN][NN_INPUT_DIM];
  int32_t b1[NN_HIDDEN];
  int16_t w2[NN_HIDDEN][NN_HIDDEN];
  int32_t b2[NN_HIDDEN];
  int16_t w3[NUM_BMODES][NN_HIDDEN];
  int32_t b3[NUM_BMODES];
} VP8NNIntra4WeightsQ;

// Rescales a raw int32 dot-product accumulator down to the next layer's
// activation scale (round-to-nearest down-shift), applies ReLU, and saturates
// to int16.
static WEBP_INLINE int16_t NNRescaleReLU(int32_t raw, int shift) {
  const int32_t rounded = (raw + (1 << (shift - 1))) >> shift;
  if (rounded <= 0) return 0;
  return (rounded > 32767) ? 32767 : (int16_t)rounded;
}

#endif  // WEBP_DSP_NN_INTRA4_DIMS_H_
