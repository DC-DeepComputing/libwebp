// Copyright 2023 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Utilities for palette analysis.
//
// Author: Vincent Rabaud (vrabaud@google.com)

#ifndef THIRD_PARTY_LIBWEBP_SRC_UTILS_PALETTE_H_
#define THIRD_PARTY_LIBWEBP_SRC_UTILS_PALETTE_H_

#include "src/webp/types.h"

#ifdef __cplusplus
extern "C" {
#endif

// The different ways a palette can be sorted.
typedef enum PaletteSorting {
  kSortedDefault = 0,
  kMinimizeDelta = 1,
  kModifiedZeng = 2,
  kUnusedPalette = 3,
} PaletteSorting;

// Given an image defined by 'src', 'src_stride', 'width' and 'height', replaces
// the indices by colors in the palette defined by 'palette' and 'palette_size'
// in the image defined by 'dst' and 'dst_stride'.
// 'xbits' is used in case pixels are bundles together using 'xbits' bits.
// Returns 0 on memory allocation error.
int ApplyPalette(const uint32_t* src, uint32_t src_stride, uint32_t* dst,
                 uint32_t dst_stride, const uint32_t* palette, int palette_size,
                 int width, int height, int xbits);

// Returns count of unique colors in 'pic', assuming pic->use_argb is true.
// If the unique color count is more than MAX_PALETTE_SIZE, returns
// MAX_PALETTE_SIZE+1.
// If 'palette' is not NULL and number of unique colors is less than or equal to
// MAX_PALETTE_SIZE, also outputs the actual unique colors into 'palette' in a
// sorted order.
// Note: 'palette' is assumed to be an array already allocated with at least
// MAX_PALETTE_SIZE elements.
struct WebPPicture;
WEBP_EXTERN int WebPGetColorPalette(const struct WebPPicture* const pic,
                                    uint32_t* const palette);

// Sorts the color sorted palette in 'palette_sorted'/'num_colors' by
// minimizing deltas between consecutive colors and stores it in 'palette'.
void PaletteSortMinimizeDeltas(const uint32_t* const palette_sorted,
                               int num_colors, uint32_t* const palette);

// Implements the modified Zeng method from "A Survey on Palette Reordering
// Methods for Improving the Compression of Color-Indexed Images" by Armando J.
// Pinho and Antonio J. R. Neves. The already palette defined by 'palette_in'
// and 'num_colors' is sorted using information from 'pic' and output in
// 'palette'.
// Returns 0 on memory allocation error.
int PaletteSortModifiedZeng(const struct WebPPicture* const pic,
                            const uint32_t* const palette_in,
                            uint32_t num_colors, uint32_t* const palette);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // THIRD_PARTY_LIBWEBP_SRC_UTILS_PALETTE_H_
