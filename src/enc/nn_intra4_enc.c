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
  // depth 1 is the source sample row above that, or a copy of depth 0 if
  // unavailable.
  for (i = 0; i < 4; ++i) dst[i] = NNPixelQ(top[i]);
  if (top_available) {
    for (i = 0; i < 4; ++i) dst[4 + i] = NNPixelQ(blk[i - BPS]);
  } else {
    memcpy(&dst[4], dst, 4 * sizeof(dst[0]));  // replicate depth 0
  }
  dst += NN_TOP;

  // depth 0: top-right reconstructed samples (top[4..7] -- the same samples
  // LD_PRED/VL_PRED read; VP8IteratorStartI4()/RotateI4() already handle all
  // the edge replication, including the right-edge-of-picture case).
  // depth 1..3: source samples further above-right, only available when the
  // block isn't in the MB's rightmost subblock column (bx4 == 3): beyond
  // that, "above-right" falls outside this MB's source buffer.
  for (i = 0; i < 4; ++i) dst[i] = NNPixelQ(top[4 + i]);
  if (top_available && bx4 < 3) {
    for (depth = 1; depth < 4; ++depth) {
      for (i = 0; i < 4; ++i) {
        dst[depth * 4 + i] = NNPixelQ(blk[4 + i - depth * BPS]);
      }
    }
  } else {
    for (depth = 1; depth < 4; ++depth) {
      memcpy(&dst[depth * 4], dst, 4 * sizeof(dst[0]));  // replicate depth 0
    }
  }
  dst += NN_TOPRIGHT;

  // Same, for left blocks. The reconstructed left column is
  // stored as top[-2-i] for row i=0 (nearest the top-left corner) to i=3
  // (bottom row).
  for (i = 0; i < 4; ++i) dst[i] = NNPixelQ(top[-2 - i]);
  if (left_available) {
    for (i = 0; i < 4; ++i) dst[4 + i] = NNPixelQ(blk[i * BPS - 1]);
  } else {
    memcpy(&dst[4], dst, 4 * sizeof(dst[0]));  // replicate depth 0
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

#ifdef WEBP_NN_INTRA4_PROFILE

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double g_nn_profile_total[NN_PROF_NUM_PHASES];
static int g_nn_profile_registered = 0;

static void PrintProfile(void) {
  static const char* const kNames[NN_PROF_NUM_PHASES] = {"gather", "score",
                                                         "select", "rd_search"};
  double total = 0.;
  int i;
  for (i = 0; i < NN_PROF_NUM_PHASES; ++i) total += g_nn_profile_total[i];
  fprintf(stderr, "=== NN intra4 profile (wall-clock seconds) ===\n");
  for (i = 0; i < NN_PROF_NUM_PHASES; ++i) {
    fprintf(stderr, "  %-10s: %8.4fs  (%5.1f%%)\n", kNames[i],
            g_nn_profile_total[i],
            (total > 0.) ? 100. * g_nn_profile_total[i] / total : 0.);
  }
  fprintf(stderr, "  %-10s: %8.4fs\n", "total", total);
}

double VP8NNIntra4ProfileNow(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

void VP8NNIntra4ProfileAdd(VP8NNProfilePhase phase, double seconds) {
  if (!g_nn_profile_registered) {
    atexit(PrintProfile);
    g_nn_profile_registered = 1;
  }
  g_nn_profile_total[phase] += seconds;
}

#endif  // WEBP_NN_INTRA4_PROFILE

#ifdef WEBP_NN_INTRA4_DUMP

#include <stdio.h>
#include <stdlib.h>

// Binary record format (read by extras/nn_intra4_train/train.py):
//   int32 quant, int32 best_mode, int16[NN_INPUT_DIM] ctx (Q14).
void VP8NNIntra4DumpSample(const int16_t ctx[NN_INPUT_DIM], int quant,
                           int best_mode) {
  static const char* path = NULL;
  static int path_checked = 0;
  FILE* f;
  if (!path_checked) {
    path = getenv("WEBP_NN_DUMP_PATH");
    path_checked = 1;
  }
  if (path == NULL) return;
  f = fopen(path, "ab");
  if (f == NULL) return;
  fwrite(&quant, sizeof(quant), 1, f);
  fwrite(&best_mode, sizeof(best_mode), 1, f);
  fwrite(ctx, sizeof(ctx[0]), NN_INPUT_DIM, f);
  fclose(f);
}

#endif  // WEBP_NN_INTRA4_DUMP
