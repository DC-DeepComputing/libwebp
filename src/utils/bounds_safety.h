#ifndef WEBP_UTILS_BOUNDS_SAFETY_H_
#define WEBP_UTILS_BOUNDS_SAFETY_H_

// Begin macros for -fbounds-safety
//
// There's some inherent complexity here due to the way -fbounds-safety works.
// Some annotations change the ABI of the function or struct (notably
// __indexable and __bidi_indexable), and so traditionally we don't want those
// annotations to "silently" disappear if they're expected.
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
// TODO: In the future, we should have CMake append to a header file (like this
// one) that libwebp was built with -fbounds-safety, so that we know to never
// make annotations vanish.

#ifndef __has_feature
#define __has_feature(x) 0
#endif

// First up, does the compiler support this?
#if __has_feature(bounds_attributes) && __has_feature(bounds_safety_attributes)
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

#endif // WEBP_UTILS_BOUNDS_SAFETY_H_
