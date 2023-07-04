// Copyright 2023 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Utilities for building and looking up Huffman trees.
//
// Author: Vincent Rabaud (vrabaud@google.com)

#ifndef THIRD_PARTY_LIBWEBP_SRC_UTILS_PALETTE_H_
#define THIRD_PARTY_LIBWEBP_SRC_UTILS_PALETTE_H_

#include "src/webp/encode.h"

typedef enum {
  kSortedDefault = 0,
  kMinimizeDelta = 1,
  kModifiedZeng = 2,
  kUnusedPalette = 3,
} PaletteSorting;

// Unique colors.

// Returns count of unique colors in 'pic', assuming pic->use_argb is true.
// If the unique color count is more than MAX_PALETTE_SIZE, returns
// MAX_PALETTE_SIZE+1.
// If 'palette' is not NULL and number of unique colors is less than or equal to
// MAX_PALETTE_SIZE, also outputs the actual unique colors into 'palette'.
// Note: 'palette' is assumed to be an array already allocated with at least
// MAX_PALETTE_SIZE elements.
WEBP_EXTERN int WebPGetColorPalette(const struct WebPPicture* const pic,
                                    uint32_t* const palette);

WEBP_EXTERN int PaletteCompareColorsForQsort(const void* p1, const void* p2);

// Returns 0 on error.
WEBP_EXTERN int ApplyPalette(const uint32_t* src, uint32_t src_stride,
                             uint32_t* dst, uint32_t dst_stride,
                             const uint32_t* palette, int palette_size,
                             int width, int height, int xbits);

WEBP_EXTERN void PaletteSortMinimizeDeltas(const uint32_t* const palette_sorted,
                                           int num_colors,
                                           uint32_t* const palette);

// Returns 0 on error.
WEBP_EXTERN int PaletteSortModifiedZeng(const WebPPicture* const pic,
                                        const uint32_t* const palette_sorted,
                                        uint32_t num_colors,
                                        uint32_t* const palette);

#endif  // THIRD_PARTY_LIBWEBP_SRC_UTILS_PALETTE_H_
