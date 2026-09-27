// Copyright 2026 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Tiny neural-net used to rank the NUM_BMODES intra4x4 prediction modes
// before the exact RD search in PickBestIntra4(). Only the top-ranked
// candidates need to go through the full reconstruct/SSE/cost evaluation path.
//
// Author: Skal (pascal.massimino@gmail.com)

#ifndef WEBP_ENC_NN_INTRA_ENC_H_
#define WEBP_ENC_NN_INTRA_ENC_H_

#include "src/dec/common_dec.h"  // for NUM_BMODES
#include "src/dsp/dsp.h"         // for VP8NNIntra4Score func
#include "src/enc/vp8i_enc.h"

#ifdef __cplusplus
extern "C" {
#endif

// Macroblock-level luma decision: selects, for the macroblock currently
// pointed to by 'it', one of the following policies. A small network predicts
// the RD-cost regret of the first three; the policy minimizing
// (predicted regret + time bias) is picked. The bias, from
// VP8NNI16ComputeBias(), is what makes the amount of pruning tunable (mu):
// Do not reorder: the network's outputs (kNNIntra16Weights) and
// kPolicyTime_cus are trained/indexed on this exact order.
typedef enum {
  NN_I16_POLICY_DC = 0,
  NN_I16_POLICY_I16,
  NN_I16_POLICY_I4,
  NN_I16_POLICY_ALL
} VP8NNI16PolicyType;
// Computes the bias of the 4 policies for a given time weight mu (in
// thousandths): mu * time / total_time, in the network's output units, plus
// nothing else.
void VP8NNI16ComputeBias(int mu_milli, int32_t bias[4]);
VP8NNI16PolicyType VP8NNI16Policy(const VP8EncIterator* WEBP_RESTRICT const it,
                                  int quant, int is_flat,
                                  const int32_t bias[4]);

// Linear "proxy" ranking of the 10 Intra4 modes into 'logits'.
void ProxyRank(const uint8_t* WEBP_RESTRICT src,
               const uint8_t* WEBP_RESTRICT preds,
               const uint16_t* WEBP_RESTRICT mode_costs, int lambda, int quant,
               int32_t logits[NUM_BMODES]);

#ifdef WEBP_NN_INTRA4_MLP
// Pixel-context MLP: 29-input int8 context (nn_intra4_dims.h), 8-bit weights.
// Same call requirements as VP8NNIntra4GatherContext().
void VP8NNIntra4GatherContext(const VP8EncIterator* WEBP_RESTRICT const it,
                              int8_t ctx[NN_INPUT_PAD]);
const VP8NNIntra4WeightsQ* VP8NNIntra4PickWeights(int quant);
#endif  // WEBP_NN_INTRA4_MLP

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // WEBP_ENC_NN_INTRA_ENC_H_
