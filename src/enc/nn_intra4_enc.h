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

#ifndef WEBP_ENC_NN_INTRA4_ENC_H_
#define WEBP_ENC_NN_INTRA4_ENC_H_

#include "src/dec/common_dec.h"  // for NUM_BMODES
#include "src/dsp/dsp.h"         // for VP8NNIntra4Score func
#include "src/dsp/nn_intra4_dims.h"
#include "src/enc/vp8i_enc.h"

#ifdef __cplusplus
extern "C" {
#endif

// The quantized weight VP8NNIntra4WeightsQ, ranges, and context layout
// (NN_BLOCK/NN_TOP/NN_TOPRIGHT/NN_LEFT/NN_CORNER) are defined in
// nn_intra4_dims.h. see that header for the full layout.

// Gathers the NN_INPUT_DIM context vector (int16, 14b fixed-point)
// for the subblock currently pointed to by 'it'. it->i4, it->i4_top must be
// valid, i.e. called between VP8IteratorStartI4()/VP8IteratorRotateI4()
// and MakeIntra4Preds()).
void VP8NNIntra4GatherContext(const VP8EncIterator* WEBP_RESTRICT const it,
                              int16_t ctx[NN_INPUT_DIM]);

// Returns the model weights to use for a given quantization (~quality)
// value VP8SegmentInfo::quant.
const VP8NNIntra4WeightsQ* VP8NNIntra4PickWeights(int quant);

#ifdef WEBP_NN_INTRA4_PROFILE
// Debug-only instrumentation for measuring where time actually goes inside
// the intra4 NN-pruning path (gather / MLP forward / top-K select) versus
// the exact RD search it feeds into. Accumulates wall-clock seconds per
// phase across the whole process and prints a summary at exit.
typedef enum {
  NN_PROF_GATHER,  // VP8NNIntra4GatherContext()
  NN_PROF_SCORE,   // VP8NNIntra4Score()
  NN_PROF_SELECT,  // top-K selection over the NUM_BMODES scores
  NN_PROF_RD,      // the exact RD search (Reconstruct/SSE/cost) it feeds
  NN_PROF_NUM_PHASES
} VP8NNProfilePhase;

double VP8NNIntra4ProfileNow(void);
void VP8NNIntra4ProfileAdd(VP8NNProfilePhase phase, double seconds);

#define NN_PROFILE_START(t) const double t = VP8NNIntra4ProfileNow()
#define NN_PROFILE_END(phase, t) \
  VP8NNIntra4ProfileAdd((phase), VP8NNIntra4ProfileNow() - (t))
#else
#define NN_PROFILE_START(t) ((void)0)
#define NN_PROFILE_END(phase, t) ((void)0)
#endif  // WEBP_NN_INTRA4_PROFILE

#ifdef WEBP_NN_INTRA4_DUMP
// Debug-only instrumentation for building a training set (see
// extras/nn_intra4_train/train.py): appends one sample (context vector,
// QP bucket key 'quant', ground-truth 'best_mode') to the file named by the
// WEBP_NN_DUMP_PATH environment variable. Does nothing if that variable is
// unset. Not thread-safe; only meant for single-threaded offline data
// collection runs.
void VP8NNIntra4DumpSample(const int16_t ctx[NN_INPUT_DIM], int quant,
                           int best_mode);
#endif  // WEBP_NN_INTRA4_DUMP

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // WEBP_ENC_NN_INTRA4_ENC_H_
