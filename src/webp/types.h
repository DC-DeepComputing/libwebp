// Copyright 2010 Google Inc. All Rights Reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the COPYING file in the root of the source
// tree. An additional intellectual property rights grant can be found
// in the file PATENTS. All contributing project authors may
// be found in the AUTHORS file in the root of the source tree.
// -----------------------------------------------------------------------------
//
//  Common types + memory wrappers
//
// Author: Skal (pascal.massimino@gmail.com)

#ifndef WEBP_WEBP_TYPES_H_
#define WEBP_WEBP_TYPES_H_

#include <stddef.h>  // IWYU pragma: export for size_t

#ifndef _MSC_VER
#include <inttypes.h>  // IWYU pragma: export
#if defined(__cplusplus) || !defined(__STRICT_ANSI__) || \
    (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L)
#define WEBP_INLINE inline
#else
#define WEBP_INLINE
#endif
#else
typedef signed   char int8_t;
typedef unsigned char uint8_t;
typedef signed   short int16_t;
typedef unsigned short uint16_t;
typedef signed   int int32_t;
typedef unsigned int uint32_t;
typedef unsigned long long int uint64_t;
typedef long long int int64_t;
#define WEBP_INLINE __forceinline
#endif  /* _MSC_VER */

#ifndef WEBP_NODISCARD
#if defined(WEBP_ENABLE_NODISCARD) && WEBP_ENABLE_NODISCARD
#if (defined(__cplusplus) && __cplusplus >= 201703L) || \
    (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L)
#define WEBP_NODISCARD [[nodiscard]]
#else
// gcc's __attribute__((warn_unused_result)) does not work for enums.
#if defined(__clang__) && defined(__has_attribute)
#if __has_attribute(warn_unused_result)
#define WEBP_NODISCARD __attribute__((warn_unused_result))
#else
#define WEBP_NODISCARD
#endif  /* __has_attribute(warn_unused_result) */
#else
#define WEBP_NODISCARD
#endif  /* defined(__clang__) && defined(__has_attribute) */
#endif  /* (defined(__cplusplus) && __cplusplus >= 201700L) ||
           (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L) */
#else
#define WEBP_NODISCARD
#endif  /* defined(WEBP_ENABLE_NODISCARD) && WEBP_ENABLE_NODISCARD */
#endif  /* WEBP_NODISCARD */

#ifndef WEBP_EXTERN
// This explicitly marks library functions and allows for changing the
// signature for e.g., Windows DLL builds.
# if defined(_WIN32) && defined(WEBP_DLL)
#  define WEBP_EXTERN __declspec(dllexport)
# elif defined(__GNUC__) && __GNUC__ >= 4
#  define WEBP_EXTERN extern __attribute__ ((visibility ("default")))
# else
#  define WEBP_EXTERN extern
# endif  /* defined(_WIN32) && defined(WEBP_DLL) */
#endif  /* WEBP_EXTERN */

// Macro to check ABI compatibility (same major revision number)
#define WEBP_ABI_IS_INCOMPATIBLE(a, b) (((a) >> 8) != ((b) >> 8))

// Begin macros for -fbounds-safety
//
// There's some inherent complexity here due to the way -fbounds-safety works.
// Some annotations change the ABI of the function (notably __indexable and
// __bidi_indexable), and so traditionally we don't want those annotations to
// "silently" disappear if they're expected.
//
// In ptrcheck.h provided by the compiler, ABI changing annotations do not
// "vanish" under any build configuration. This intentional. Consider the
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
// TODO: Have CMake append to a header file (like this one) that libwebp was
// built with -fbounds-safety, so that we know to never make annotations
// vanish.

// First up, does the compiler support this?
#if defined(__has_feature) && __has_feature(bounds_attributes) && \
                              __has_feature(bounds_safety_attributes)
#define _WEBP_COMPILER_SUPPORTS_FBOUNDS_SAFETY 1
#else
#define _WEBP_COMPILER_SUPPORTS_FBOUNDS_SAFETY 0
#endif

// Did the user request this but the compiler doesn't support it?
#if WEBP_ENABLE_FBOUNDS_SAFETY && !_WEBP_COMPILER_SUPPORTS_FBOUNDS_SAFETY
#error Attempted to build with -fbounds-safety which is not supported by the current compiler.

// User requested it and compiler supports it
#elif WEBP_ENABLE_FBOUNDS_SAFETY && _WEBP_COMPILER_SUPPORTS_FBOUNDS_SAFETY
#include <ptrcheck.h>

#define WEBP_ASSUME_UNSAFE_INDEXABLE_ABI __ptrcheck_abi_assume_unsafe_indexable()

#define WEBP_COUNTED_BY(x) __counted_by(x)
#define WEBP_SIZED_BY(x) __sized_by(x)
#define WEBP_UNSAFE_INDEXABLE __unsafe_indexable
#define WEBP_SINGLE __single

#define WEBP_INDEXABLE __indexable
#define WEBP_BIDI_INDEXABLE __bidi_indexable

#define WEBP_UNSAFE_FORGE_BIDI_INDEXABLE(typ, ptr, size) \
  __unsafe_forge_bidi_indexable(typ, ptr, size)

// Provide memcpy/memset/memmove wrappers to make migration easier.
#define WEBP_UNSAFE_MEMCPY(dst, src, size) do { \
  memcpy(WEBP_UNSAFE_FORGE_BIDI_INDEXABLE(uint8_t*, dst, size), \
         WEBP_UNSAFE_FORGE_BIDI_INDEXABLE(uint8_t*, src, size), \
         size); \
  } while (0)

#define WEBP_UNSAFE_MEMSET(dst, c, size) do { \
  memset(WEBP_UNSAFE_FORGE_BIDI_INDEXABLE(uint8_t*, dst, size), c, size); \
  } while (0)

#define WEBP_UNSAFE_MEMMOVE(dst, src, size) do { \
  memmove(WEBP_UNSAFE_FORGE_BIDI_INDEXABLE(uint8_t*, dst, size), \
         WEBP_UNSAFE_FORGE_BIDI_INDEXABLE(uint8_t*, src, size), \
         size); \
  } while (0)

#else

#define WEBP_ASSUME_UNSAFE_INDEXABLE_ABI

#define WEBP_COUNTED_BY(x)
#define WEBP_SIZED_BY(x)
#define WEBP_UNSAFE_INDEXABLE
#define WEBP_SINGLE

#define WEBP_INDEXABLE
#define WEBP_BIDI_INDEXABLE

#define WEBP_UNSAFE_MEMCPY(dst, src, size) memcpy(dst, src, size)
#define WEBP_UNSAFE_MEMSET(dst, c, size) memset(dst, c, size)
#define WEBP_UNSAFE_MEMMOVE(dst, src, size) memmove(dst, src, size)

#define WEBP_UNSAFE_FORGE_BIDI_INDEXABLE(typ, ptr, size) ((typ)(ptr))

#endif

// End macros for -fbounds-safety

#ifdef __cplusplus
extern "C" {
#endif

// Allocates 'size' bytes of memory. Returns NULL upon error. Memory
// must be deallocated by calling WebPFree(). This function is made available
// by the core 'libwebp' library.
WEBP_NODISCARD WEBP_EXTERN void* WebPMalloc(size_t size);

// Releases memory returned by the WebPDecode*() functions (from decode.h).
WEBP_EXTERN void WebPFree(void* ptr);

#ifdef __cplusplus
}    // extern "C"
#endif

#endif  // WEBP_WEBP_TYPES_H_
