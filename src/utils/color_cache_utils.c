// Copyright 2012 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Color Cache for WebP Lossless
//
// Author: Jyrki Alakuijala (jyrki@google.com)

#include "src/utils/color_cache_utils.h"

#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "src/utils/bounds_safety.h"
#include "src/utils/utils.h"
#include "src/webp/types.h"

WEBP_ASSUME_UNSAFE_INDEXABLE_ABI

//------------------------------------------------------------------------------
// VP8LColorCache.

int VP8LColorCacheInit(VP8LColorCache* const color_cache, int hash_bits) {
  const int hash_size = 1 << hash_bits;
  assert(color_cache != NULL);
  assert(hash_bits > 0);
<<<<<<< PATCH SET (f0f8ab440a0514d4ee7a65a59a6bcc6ad9b05ba1 Adds fbounds annotations for VP8LColorCache pointer.)
  {
    // Allocate first, check for NULL, then assign members side-by-side.
    // WebPSafeCalloc result is __unsafe_indexable when suppress_fbounds_errors=yes.
    uint32_t* __unsafe_indexable const unsafe_allocated_colors = (uint32_t*)WebPSafeCalloc(
      (uint64_t)hash_size, sizeof(*color_cache->colors));
    if (unsafe_allocated_colors == NULL) {
      // Assign NULL and perform self-assignment for hash_bits side-by-side.
      color_cache->colors = NULL; // Match original behavior on failure
      color_cache->hash_bits = color_cache->hash_bits; // Required by __counted_by
      return 0;
    }
    // Success path: assign side-by-side
    color_cache->colors = __unsafe_forge_bidi_indexable(uint32_t*, unsafe_allocated_colors, hash_size);
    color_cache->hash_bits = hash_bits;
    color_cache->hash_shift = 32 - hash_bits;
  }
||||||| BASE      (4e63ff1eb6a7c8b23911fb38375ba7ee162cce34 Fix lossy/lossless typo in anim_encode)
  color_cache->colors = (uint32_t*)WebPSafeCalloc(
      (uint64_t)hash_size, sizeof(*color_cache->colors));
  if (color_cache->colors == NULL) return 0;
  color_cache->hash_shift = 32 - hash_bits;
  color_cache->hash_bits = hash_bits;
=======
  color_cache->colors = (uint32_t*)WebPSafeCalloc((uint64_t)hash_size,
                                                  sizeof(*color_cache->colors));
  if (color_cache->colors == NULL) return 0;
  color_cache->hash_shift = 32 - hash_bits;
  color_cache->hash_bits = hash_bits;
>>>>>>> BASE      (456e2cbce19a0e1ebda50a7f807a4729648a7a82 VP8LInitBitReader: remove dead store)
  return 1;
}

void VP8LColorCacheClear(VP8LColorCache* const color_cache) {
  if (color_cache != NULL) {
    WebPSafeFree(color_cache->colors);
    color_cache->colors = NULL;
    // Self-assignment required by __counted_by when colors is assigned.
    color_cache->hash_bits = color_cache->hash_bits;
  }
}

void VP8LColorCacheCopy(const VP8LColorCache* const src,
                        VP8LColorCache* const dst) {
  assert(src != NULL);
  assert(dst != NULL);
  assert(src->hash_bits == dst->hash_bits);
  WEBP_UNSAFE_MEMCPY(dst->colors, src->colors,
                     ((size_t)1u << dst->hash_bits) * sizeof(*dst->colors));
}
