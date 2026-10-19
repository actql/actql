#ifndef ACTQL_NATIVE_INITIAL_LOADER_ENVIRONMENT_H
#define ACTQL_NATIVE_INITIAL_LOADER_ENVIRONMENT_H

#include <stdbool.h>
#include <stddef.h>
#if defined(__APPLE__)
#include <crt_externs.h>
#endif

/* Conditions of the selected fixed Native loader recipe only. This scan has
 * no allocator or libc string calls: at most 10000 vector slots and five
 * bytes per non-NULL entry. An empty vector is valid; a missing vector or a
 * vector without its terminator inside that bound is unsupported. Entries
 * are the platform's valid NUL-terminated environment strings, not arbitrary
 * caller-provided memory. Values and unrelated names are not copied/scanned.
 * DYLD_* names are case-sensitive, as in the selected Darwin environment. */
#define ACTQL_NATIVE_LOADER_ENVIRONMENT_SLOTS ((size_t)10000)
static inline bool actql_native_loader_environment_vector_supported(
    char *const *environment) {
  static const char prefix[] = "DYLD_";
  if (!environment) return false;
  for (size_t i = 0; i < ACTQL_NATIVE_LOADER_ENVIRONMENT_SLOTS; ++i) {
    const char *text = environment[i];
    if (!text) return true;
    size_t j = 0;
    while (j < sizeof(prefix)-1 && text[j] == prefix[j]) ++j;
    if (j == sizeof(prefix)-1) return false;
  }
  return false;
}

enum actql_native_loader_environment_state {
  ACTQL_LOADER_ENVIRONMENT_UNOBSERVED,
  ACTQL_LOADER_ENVIRONMENT_SUPPORTED,
  ACTQL_LOADER_ENVIRONMENT_REFUSED
};

/* Embedded in the existing actual entry, never an OS original or capacity
 * issuer. The entry independently checks nominal startup/generation, process,
 * thread and its complete recipe. A copy of this observation proves none of
 * those facts. There is no constructor, environment mutation or reset here. */
typedef struct {
  enum actql_native_loader_environment_state state;
} actql_native_loader_environment;

static inline bool actql_native_loader_environment_now_supported(void) {
#if defined(__APPLE__)
  char ***slot = _NSGetEnviron();
  return slot && actql_native_loader_environment_vector_supported(*slot);
#else
  return false; /* No other platform is selected by this private recipe. */
#endif
}

static inline bool actql_native_loader_environment_capture(
    actql_native_loader_environment *observation) {
  if (!observation || observation->state != ACTQL_LOADER_ENVIRONMENT_UNOBSERVED)
    return false;
  observation->state = actql_native_loader_environment_now_supported()
    ? ACTQL_LOADER_ENVIRONMENT_SUPPORTED : ACTQL_LOADER_ENVIRONMENT_REFUSED;
  return observation->state == ACTQL_LOADER_ENVIRONMENT_SUPPORTED;
}

/* Recheck before normal covered work. Observed refusal is sticky even if an
 * environment entry is subsequently removed; it cannot reissue startup or a
 * load attempt. Cleanup of the same partial receiver does not use this normal
 * predicate. Absence of DYLD_* cannot prove that an image was never injected
 * or that prior platform initialization had any particular allocation bound. */
static inline bool actql_native_loader_environment_current(
    actql_native_loader_environment *observation) {
  if (!observation || observation->state != ACTQL_LOADER_ENVIRONMENT_SUPPORTED)
    return false;
  if (!actql_native_loader_environment_now_supported()) {
    observation->state = ACTQL_LOADER_ENVIRONMENT_REFUSED;
    return false;
  }
  return true;
}

#endif
