#ifndef ACTQL_OWNED_LINUX_X64_PROCESS_PROFILE_H
#define ACTQL_OWNED_LINUX_X64_PROCESS_PROFILE_H

/* Compile-time selection only. This does not issue a Core child, borrow,
 * capacity or stop acknowledgement, or select an image/Rust runtime. */
#if !defined(ACTQL_NATIVE_OWNED_LINUX_X64_PROCESS_DOMAIN) || \
    !defined(__linux__) || !defined(__x86_64__) || !defined(__LP64__)
#error "The owned Linux x64 process profile requires its explicit actual target"
#endif
#if defined(ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN) || \
    defined(ACTQL_SCOPED_READ_ALLOCATOR) || defined(ACTQL_SCOPED_READ_PROVIDER) || \
    defined(ACTQL_BOOTSTRAP_IMPORT_PROVIDER)
#error "The owned Linux x64 process profile cannot substitute another provider"
#endif
#if !defined(_GNU_SOURCE)
#error "Select _GNU_SOURCE before the translation unit's system headers"
#endif

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>
#include <sys/types.h>

#if !defined(__GLIBC__)
#error "The owned Linux x64 process profile requires glibc"
#endif
#if !defined(__BYTE_ORDER__) || __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "The owned Linux x64 process profile requires little-endian layout"
#endif

/* Shared controls contain relative size_t ranges and atomic PID records.
 * Producer and consumer must use the same profile and original recipe. Do not
 * replace these checks with copied Darwin/ARM structure sizes. */
_Static_assert(CHAR_BIT == 8, "Owned process byte width");
_Static_assert(sizeof(void *) == 8 && sizeof(uintptr_t) == 8,
               "Owned process pointer width");
_Static_assert(sizeof(size_t) == 8 && sizeof(ptrdiff_t) == 8 && sizeof(long) == 8,
               "Owned process LP64 ranges");
_Static_assert(sizeof(off_t) == 8, "Owned process FD offset width");
_Static_assert(sizeof(int) == 4 && sizeof(pid_t) == 4,
               "Owned process atomic PID representation");
_Static_assert(sizeof(atomic_int) == sizeof(int),
               "Owned process shared atomic PID width");
_Static_assert(sizeof(uint64_t) == 8 && sizeof(int64_t) == 8,
               "Owned process Moon/C scalar width");
_Static_assert(ATOMIC_INT_LOCK_FREE == 2,
               "Owned process shared PID atomics must always be lock-free");

#endif
