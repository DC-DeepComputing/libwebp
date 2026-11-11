// Copyright 2025 Google LLC
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
// Adds compatibility / portability macros to support usage of -fbounds-safety

#ifndef WEBP_UTILS_BOUNDS_SAFETY_H_
#define WEBP_UTILS_BOUNDS_SAFETY_H_

/* CMake generates webp_bounds_safety_build.h in the build directory and
 * installs it next to this header. Include it so a consumer of a
 * -fbounds-safety build still sees ABI-changing annotations even if they
 * did not pass -DWEBP_SUPPORT_FBOUNDS_SAFETY.
 * See https://issues.webmproject.org/432511225.
 */
#ifndef WEBP_SUPPORT_FBOUNDS_SAFETY
#if defined(__has_include)
#if __has_include("webp_bounds_safety_build.h")
#include "webp_bounds_safety_build.h"
#elif __has_include("webp/webp_bounds_safety_build.h")
#include "webp/webp_bounds_safety_build.h"
#endif
#endif  /* defined(__has_include) */
#endif  /* WEBP_SUPPORT_FBOUNDS_SAFETY */

#ifdef WEBP_SUPPORT_FBOUNDS_SAFETY

#include <ptrcheck.h>
//
// There's some inherent complexity here due to the way -fbounds-safety works.
// Some annotations (notably __indexable and __bidi_indexable) change the ABI
// of the function or struct, so we don't want those annotations to silently
// disappear if they're expected.
//
// In ptrcheck.h provided by the compiler, ABI changing annotations do not
// "vanish" under any build configuration. This is intentional. Consider the
// following example:
//
// == Safe.h, where Safe.c is always compiled with -fbounds-safety ==
// Forward declare my_function, implemented in Safe.c
// void my_function(char *__bidi_indexable ptr);
//
// If we have a project that does not use -fbounds-safety, and we want to call
// my_function that was pre-built with -fbounds-safety, this annotation cannot
// vanish or there'll be an ABI mismatch, which may fail to compile or have
// worse behaviors at runtime.
//
// CMake generates and installs src/webp/webp_bounds_safety_build.h (included
// above) so a -fbounds-safety build of libwebp records WEBP_SUPPORT_FBOUNDS_SAFETY
// for consumers. See https://issues.webmproject.org/432511225.

// The annotations below are ABI breaking as they turn normal pointers into
// "wide" pointers. Breaking them down:
// * __indexable is akin to { ptr_curr, ptr_end }, and can only be
//   forward-indexed.
// * __bidi_indexable (bidirectional indexable) is
//   { ptr_begin, ptr_curr, ptr_end }
//   and can be both forward and backward indexed.
// See https://clang.llvm.org/docs/BoundsSafety.html for more comprehensive
// documentation
#define WEBP_INDEXABLE __indexable
#define WEBP_BIDI_INDEXABLE __bidi_indexable

#else  // WEBP_SUPPORT_FBOUNDS_SAFETY

#define WEBP_INDEXABLE
#define WEBP_BIDI_INDEXABLE

#endif  // WEBP_SUPPORT_FBOUNDS_SAFETY

#endif  // WEBP_UTILS_BOUNDS_SAFETY_H_
