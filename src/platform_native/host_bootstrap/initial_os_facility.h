#ifndef ACTQL_NATIVE_INITIAL_OS_FACILITY_H
#define ACTQL_NATIVE_INITIAL_OS_FACILITY_H

#include "command_platform.h"
#include "initial_loader_environment.h"
#include <pthread.h>
#include <unistd.h>

/* Defined by the one selected executable entry. It checks the real initial
 * executable/source/generation, process, main thread, stack and captured input
 * before managed startup or later Runtime registration. This borrow cannot be
 * reconstructed from arguments and does not require managed_current. */
actql_native_command_platform_original *
actql_native_command_platform_initial_current(void);

typedef struct {
  actql_native_command_platform_original *entry;
  pid_t process;
  pthread_t thread;
  actql_native_loader_environment environment;
  bool normal_refused;
} actql_native_initial_os_facility;

/* Included only in the existing initial entry TU: one lifetime and one
 * observation, not one registration per component or phase. This is the
 * selected platform's process/thread service original, not a mapped extent,
 * byte allowance, demand estimate, or numerical capacity field. It has no
 * release/refill/transfer operation. The original process retains platform
 * state even after individual component/module acknowledgements. */
static actql_native_initial_os_facility actql_initial_os_facility;
static bool actql_initial_os_facility_attempted;

static inline actql_native_initial_os_facility *
actql_native_initial_os_facility_capture(void) {
#if defined(__APPLE__) && defined(__aarch64__) && \
    defined(ACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY) && \
    defined(ACTQL_NATIVE_CLIENT_SOURCE_SHA)
  if (actql_initial_os_facility_attempted) return NULL;
  actql_initial_os_facility_attempted = true;
  actql_native_command_platform_original *entry =
    actql_native_command_platform_initial_current();
  if (!entry) return NULL;
  actql_initial_os_facility.entry = entry;
  actql_initial_os_facility.process = getpid();
  actql_initial_os_facility.thread = pthread_self();
  /* Return the same partial observation on unsupported conditions. The entry
   * must check current before its covered work; capture alone is no admission. */
  (void)actql_native_loader_environment_capture(
    &actql_initial_os_facility.environment);
  return &actql_initial_os_facility;
#else
  return NULL;
#endif
}

static inline bool actql_native_initial_os_facility_current(
    actql_native_initial_os_facility *original) {
#if defined(__APPLE__) && defined(__aarch64__) && \
    defined(ACTQL_NATIVE_COMMAND_OPERATIONAL_ENTRY) && \
    defined(ACTQL_NATIVE_CLIENT_SOURCE_SHA)
  /* Nominal identity precedes dereferencing foreign/copied observations. A
   * foreign thread/fork cannot consume or invalidate the original's cleanup. */
  if (original != &actql_initial_os_facility ||
      !actql_initial_os_facility_attempted || !original->entry ||
      original->process != getpid() ||
      !pthread_equal(original->thread, pthread_self()))
    return false;
  if (original->normal_refused) return false;
  if (actql_native_command_platform_initial_current() != original->entry ||
      !actql_native_loader_environment_current(&original->environment)) {
    original->normal_refused = true;
    return false;
  }
  return true;
#else
  (void)original;
  return false;
#endif
}

/* The entry and its existing two one-shot load records still bind each
 * SQLite/Crypto attempt to the actual observed member, Runtime, installation
 * and generation before dlopen. Each component validates its original provider
 * and fixed symbol origins. No path/manifest supplied to this header could
 * create that association. Normal use requires this current predicate;
 * same-original partial cleanup keeps its separate existing carriers. */

#endif
