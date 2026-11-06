#include "moonbit.h"

#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#if defined(__APPLE__)
#include <crt_externs.h>
#endif
#if defined(__APPLE__) || (defined(__linux__) && defined(__x86_64__) && defined(__GLIBC__))
#define ACTQL_NATIVE_COMMAND_RAW_ARGUMENTS 1
// The selected pinned libmoonbitrun.o supplies this mimalloc size query.
// It is the same allocator used before the derived Read context is entered.
extern size_t mi_good_size(size_t size);
#endif

#include "../../platform_native/host_bootstrap/command_input.h"
#include <sys/time.h>
#include <time.h>

int32_t actql_native_client_write_stdout(moonbit_bytes_t bytes, int32_t length) {
  if (length < 0) return 0;
  if (fwrite(bytes, 1, (size_t)length, stdout) != (size_t)length) return 0;
  return fflush(stdout) == 0;
}

// Report the original operation failure while its managed aliases are alive.
// The caller still performs each independent cleanup before the final exit.
void actql_native_client_report_failure(moonbit_bytes_t bytes, int32_t length) {
  if (length >= 0) fwrite(bytes, 1, (size_t)length, stderr);
  fputc('\n', stderr);
  fflush(stderr);
}
void actql_native_client_exit_failure(void) { exit(1); }
void actql_native_client_exit_argument_failure(void) { exit(2); }

void actql_native_client_fail(moonbit_bytes_t bytes, int32_t length) {
  if (length >= 0) fwrite(bytes, 1, (size_t)length, stderr);
  fputc('\n', stderr);
  fflush(stderr);
  exit(1);
}

int32_t actql_native_client_flush_stdout(void) {
  return fflush(stdout) == 0;
}

int32_t actql_native_client_utc_now(moonbit_bytes_t bytes, int32_t length) {
  struct timeval now;
  struct tm utc;
  char date[20];
  if (length != 25 || gettimeofday(&now, NULL) != 0 ||
      gmtime_r(&now.tv_sec, &utc) == NULL ||
      strftime(date, sizeof(date), "%Y-%m-%dT%H:%M:%S", &utc) != 19)
    return 0;
  return snprintf((char *)bytes, (size_t)length, "%s.%03dZ", date,
                  (int)(now.tv_usec / 1000)) == 24;
}

// One CLI observation scope. Signals request ending the watch; the existing
// Host/Store owner must still close its original resources before returning.
static volatile sig_atomic_t actql_status_interrupted;
static bool actql_status_watching;
static struct sigaction actql_status_old_int, actql_status_old_term;
static void actql_status_on_signal(int number) {
  (void)number;
  actql_status_interrupted = 1;
}

int32_t actql_native_client_status_watch_begin(void) {
  if (actql_status_watching) return 0;
  struct sigaction selected;
  selected.sa_handler = actql_status_on_signal;
  sigemptyset(&selected.sa_mask);
  selected.sa_flags = 0;
  if (sigaction(SIGINT, NULL, &actql_status_old_int) != 0 ||
      sigaction(SIGTERM, NULL, &actql_status_old_term) != 0) return 0;
  actql_status_interrupted = 0;
  if (sigaction(SIGINT, &selected, NULL) != 0) return 0;
  actql_status_watching = true;
  // The same command cleanup path handles even partial installation.
  if (sigaction(SIGTERM, &selected, NULL) != 0) return 0;
  return 1;
}

int32_t actql_native_client_status_watch_end(void) {
  if (!actql_status_watching) return 1;
  // An unconfirmed restoration remains pending, never reported as closed.
  int first = sigaction(SIGINT, &actql_status_old_int, NULL);
  int second = sigaction(SIGTERM, &actql_status_old_term, NULL);
  if (first != 0 || second != 0) return 0;
  actql_status_watching = false;
  return 1;
}

int32_t actql_native_client_status_watch_interrupted(void) {
  return actql_status_interrupted ? 1 : 0;
}

int64_t actql_native_client_status_watch_now(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec < 0 ||
      now.tv_sec > (INT64_MAX - 999) / 1000) return -1;
  return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

int32_t actql_native_client_status_watch_pause(int32_t milliseconds) {
  if (milliseconds <= 0 || milliseconds > 100) return 0;
  struct timespec remaining = {
    .tv_sec = 0, .tv_nsec = (long)milliseconds * 1000000L
  };
  while (nanosleep(&remaining, &remaining) != 0) {
    if (errno != EINTR) return 0;
    if (actql_status_interrupted) return 1;
  }
  return 1;
}

int32_t actql_native_client_status_watch_progress(moonbit_bytes_t bytes, int32_t length) {
  if (length < 0 || length > 65537) return 0;
  return fwrite(bytes, 1, (size_t)length, stderr) == (size_t)length &&
    fflush(stderr) == 0;
}

// Build metadata only. The trusted Local producer pins this immutable literal
// to its exact compiled source; it is not installation/current authority. A raw
// bounded input capture may borrow it without a Moon String allocation. The
// ordinary unselected diagnostic build supplies no synthetic replacement pin.
const char *actql_native_client_selected_source(void) {
#ifdef ACTQL_NATIVE_CLIENT_SOURCE_SHA
  static const char source[] = ACTQL_NATIVE_CLIENT_SOURCE_SHA;
  if (sizeof(source) != 41) return NULL;
  for (size_t i = 0; i < 40; ++i) {
    if (!((source[i] >= '0' && source[i] <= '9') ||
          (source[i] >= 'a' && source[i] <= 'f'))) return NULL;
  }
  return source;
#else
  return NULL;
#endif
}

/* Actual compiler target observation only. Launcher metadata cannot select a
 * foreign physical profile; this does not issue a Host or component original. */
int32_t actql_native_client_compiled_platform(void) {
#if defined(__APPLE__) && defined(__aarch64__)
  return 1;
#elif defined(__linux__) && defined(__x86_64__) && defined(__GLIBC__)
  return 2;
#else
  return 0;
#endif
}

// The OS argv and launcher marker stay in their original process lifetime.
// This private observation performs no managed copy or physical acquisition.
// Once selected or refused it cannot restart against changed process inputs.
static bool actql_command_input_attempted;
static int actql_command_input_status = ACTQL_COMMAND_INPUT_INVALID;
static const char *actql_command_input_source;
static const char *actql_command_input_context;
static char actql_command_input_scratch[ACTQL_COMMAND_SCRATCH_BYTES + 1];
static char actql_command_original_context[ACTQL_COMMAND_ORIGINAL_CONTEXT_BYTES + 1];
static unsigned char actql_command_original_arguments[ACTQL_COMMAND_ORIGINAL_ARGUMENT_BYTES];
static bool actql_command_early_input_attempted;
static int actql_command_early_input_status = ACTQL_COMMAND_INPUT_INVALID;
static actql_bootstrap_command_preparation_observation actql_command_input;
// Partial initial-control inventory, not capacity or an allocation receipt.
// These are the selected pinned mimalloc usable classes for the original raw argv,
// worst-case UTF16 decode/trim overlap, and every growing argv ref buffer.
static int64_t actql_command_argument_classes[4];

#if defined(__linux__) && defined(__x86_64__) && defined(__GLIBC__)
/* glibc supplies the original executable arguments to init-array functions.
 * Retain only their process-lived pointers, as the existing Linux command
 * entry does. No input read, allocation, environment or Host is acquired here. */
static struct { bool seen; int argc; char **argv; } actql_command_linux_arguments;
__attribute__((constructor(101)))
static void actql_command_capture_linux_arguments(int argc, char **argv, char **environment) {
  (void)environment;
  if (actql_command_linux_arguments.seen) return;
  actql_command_linux_arguments.seen = true;
  actql_command_linux_arguments.argc = argc;
  actql_command_linux_arguments.argv = argv;
}
#endif

#if defined(ACTQL_NATIVE_COMMAND_RAW_ARGUMENTS)
static bool actql_command_raw_arguments(int *argc, const char *const **argv) {
#if defined(__APPLE__)
  if (!_NSGetArgc() || !_NSGetArgv()) return false;
  *argc = *_NSGetArgc();
  *argv = (const char *const *)*_NSGetArgv();
#else
  if (!actql_command_linux_arguments.seen) return false;
  *argc = actql_command_linux_arguments.argc;
  *argv = (const char *const *)actql_command_linux_arguments.argv;
#endif
  return *argc > 0 && *argv != NULL;
}

static bool actql_command_add_class(int64_t *sum, size_t request) {
  size_t quoted = mi_good_size(request);
  if (quoted < request || quoted > INT64_MAX ||
      *sum > INT64_MAX - (int64_t)quoted) return false;
  *sum += (int64_t)quoted;
  return true;
}

static bool actql_command_quote_arguments(int argc, const char *const *argv) {
  int64_t values[4] = {0};
  const size_t header = sizeof(struct moonbit_object);
  if (argc <= 0 || (size_t)argc > (SIZE_MAX-header)/sizeof(void *) ||
      !actql_command_add_class(&values[0], header+(size_t)argc*sizeof(void *)))
    return false;
  for (int index = 0; index < argc; ++index) {
    size_t bytes = strlen(argv[index]);
    if (bytes > (SIZE_MAX-header)/2-1 ||
        !actql_command_add_class(&values[1], header+bytes+1) ||
        !actql_command_add_class(&values[2], header+2*(bytes+1)) ||
        !actql_command_add_class(&values[2], header+2*(bytes+1))) return false;
  }
  // Pinned env_native uses an empty Array then push. Its ref buffers begin
  // at eight and double; retain the conservative sum of all generations.
  size_t capacity = 8;
  for (;;) {
    if (capacity > (SIZE_MAX-header)/sizeof(void *) ||
        !actql_command_add_class(&values[3], header+capacity*sizeof(void *)))
      return false;
    if (capacity >= (size_t)argc) break;
    if (capacity > SIZE_MAX/2) return false;
    capacity *= 2;
  }
  memcpy(actql_command_argument_classes, values, sizeof(values));
  return true;
}
#endif

/* Normal main bounds and copies the selected input before command parsing.
 * These finite input checks are not startup provenance or resource authority. */
static void actql_native_client_capture_initial_input(void) {
  if (actql_command_early_input_attempted) return;
  actql_command_early_input_attempted = true;
  const char *context = getenv("ACTQL_NATIVE_LOCAL_RUNTIME");
  if (context == NULL) {
    actql_command_early_input_status = ACTQL_COMMAND_INPUT_NOT_SELECTED;
    return;
  }
#if defined(ACTQL_NATIVE_COMMAND_RAW_ARGUMENTS)
  const char *source = actql_native_client_selected_source();
  int argc = 0;
  const char *const *argv = NULL;
  if (!actql_command_raw_arguments(&argc, &argv)) return;
  actql_command_early_input_status = actql_bootstrap_measure_command_preparation(
      source, context, argc, argv,
      ACTQL_COMMAND_ORIGINAL_ARGUMENT_BYTES, ACTQL_COMMAND_ORIGINAL_ARGUMENT_BYTES,
      ACTQL_COMMAND_ORIGINAL_ARGUMENT_BYTES, ACTQL_COMMAND_ORIGINAL_CONTEXT_BYTES,
      &actql_command_input);
  if (actql_command_early_input_status != ACTQL_COMMAND_INPUT_OK) return;
  size_t offset = 0;
  for (int index = 0; index < argc; ++index) {
    for (size_t byte = 0;; ++byte) {
      if (offset >= sizeof(actql_command_original_arguments)) {
        actql_command_early_input_status = ACTQL_COMMAND_INPUT_TOTAL_BYTES;
        return;
      }
      unsigned char value = (unsigned char)argv[index][byte];
      actql_command_original_arguments[offset++] = value;
      if (value == 0) break;
    }
  }
  if (offset != actql_command_input.input.storage_bytes ||
      !actql_command_quote_arguments(argc, argv)) {
    actql_command_early_input_status = ACTQL_COMMAND_INPUT_INVALID;
    return;
  }
  memcpy(actql_command_original_context, context,
      actql_command_input.context_bytes + 1);
  actql_command_early_input_status = actql_bootstrap_capture_command_scratch(
        getenv("TMPDIR"), actql_command_input_scratch);
  if (actql_command_early_input_status == ACTQL_COMMAND_INPUT_OK) {
    actql_command_input_source = source;
    actql_command_input_context = actql_command_original_context;
  }
#endif
}

static bool actql_command_original_arguments_current(void) {
#if defined(ACTQL_NATIVE_COMMAND_RAW_ARGUMENTS)
  int argc = 0;
  const char *const *argv = NULL;
  if (!actql_command_raw_arguments(&argc, &argv) ||
      (size_t)argc != actql_command_input.input.arguments)
    return false;
  size_t offset = 0;
  for (int index = 0; index < argc; ++index) {
    if (argv[index] == NULL) return false;
    for (size_t byte = 0;; ++byte) {
      if (offset >= actql_command_input.input.storage_bytes) return false;
      unsigned char original = actql_command_original_arguments[offset++];
      if ((unsigned char)argv[index][byte] != original) return false;
      if (original == 0) break;
    }
  }
  return offset == actql_command_input.input.storage_bytes;
#else
  return false;
#endif
}

int32_t actql_native_client_measure_prearguments(
    int32_t maximum_arguments, int32_t maximum_argument_bytes,
    int32_t maximum_storage_bytes, int32_t maximum_context_bytes) {
  if (actql_command_input_attempted) return actql_command_input_status;
  actql_command_input_attempted = true;
  actql_native_client_capture_initial_input();
  if (!actql_command_early_input_attempted) return actql_command_input_status;
  actql_command_input_status = actql_command_early_input_status;
  if (actql_command_input_status != ACTQL_COMMAND_INPUT_OK)
    return actql_command_input_status;
  if (maximum_arguments <= 0 || maximum_argument_bytes <= 0 ||
      maximum_storage_bytes <= 0 || maximum_context_bytes <= 0 ||
      !actql_command_original_arguments_current())
    actql_command_input_status = ACTQL_COMMAND_INPUT_INVALID;
  else if (actql_command_input.context_bytes > (size_t)maximum_context_bytes)
    actql_command_input_status = ACTQL_COMMAND_INPUT_CONTEXT;
  else if (actql_command_input.input.arguments > (size_t)maximum_arguments)
    actql_command_input_status = ACTQL_COMMAND_INPUT_ARGUMENTS;
  else if (actql_command_input.input.longest_argument_bytes > (size_t)maximum_argument_bytes)
    actql_command_input_status = ACTQL_COMMAND_INPUT_ARGUMENT_BYTES;
  else if (actql_command_input.input.storage_bytes > (size_t)maximum_storage_bytes)
    actql_command_input_status = ACTQL_COMMAND_INPUT_TOTAL_BYTES;
  return actql_command_input_status;
}

int32_t actql_native_client_preargument_count(void) {
  return actql_command_input_status == ACTQL_COMMAND_INPUT_OK
      ? (int32_t)actql_command_input.input.arguments : -1;
}
/* Selection is the original one-shot observation, never a later environment
 * probe or an operational/permission receipt. Invalid/unmeasured input cannot
 * choose the unselected compatibility entrance. */
int32_t actql_native_client_preargument_selection(void) {
  return actql_command_input_attempted
      ? actql_command_input_status : ACTQL_COMMAND_INPUT_INVALID;
}
int32_t actql_native_client_preargument_storage_bytes(void) {
  return actql_command_input_status == ACTQL_COMMAND_INPUT_OK
      ? (int32_t)actql_command_input.input.storage_bytes : -1;
}
int32_t actql_native_client_preargument_context_bytes(void) {
  return actql_command_input_status == ACTQL_COMMAND_INPUT_OK
      ? (int32_t)actql_command_input.context_bytes : -1;
}

// The 40-byte compiler literal is part of the declared initial control graph.
// The bounded context copy is also initial control, before physical acquisition.
// Neither copied value is installation/current/admission authority.
int32_t actql_native_client_copy_preargument_source(
    moonbit_bytes_t bytes, int32_t length) {
  if (actql_command_input_status != ACTQL_COMMAND_INPUT_OK || length != 40 ||
      actql_command_input_source == NULL) return 0;
  memcpy(bytes, actql_command_input_source, 40);
  return 1;
}
int32_t actql_native_client_copy_preargument_context(
    moonbit_bytes_t bytes, int32_t length) {
  if (actql_command_input_status != ACTQL_COMMAND_INPUT_OK || length <= 0 ||
      (size_t)length != actql_command_input.context_bytes ||
      actql_command_input_context == NULL) return 0;
  memcpy(bytes, actql_command_input_context, (size_t)length);
  return 1;
}

// Closed private selectors: raw reference array, raw Bytes, simultaneous
// UTF16 temporary+result upper bound, all argv growth backings. Record objects,
// parser/maps/rendering and later physical overlap remain separate terms.
int64_t actql_native_client_preargument_class_bytes(int32_t field) {
  if (actql_command_input_status != ACTQL_COMMAND_INPUT_OK ||
      field < 0 || field >= 4) return -1;
  return actql_command_argument_classes[field];
}

// A caller-lifetime barrier only. The opaque managed record is not inspected,
// stored, released or interpreted as physical custody or an acknowledgement.
void actql_native_client_keep_initial_command_control(const void *original) {
  const void *volatile observed = original;
  (void)observed;
}

// One selected HOME observation, not an environment traversal or authority.
// The existing path predicate bounds decoded UTF16 to 4096 units. At most
// three UTF8 bytes per such unit, plus one optional BOM, preserves that domain.
// Scan before copying; malformed/oversized input cannot cause an unbounded
// managed environment copy. The caller owns this fixed output workspace.
int32_t actql_native_client_copy_bounded_home(moonbit_bytes_t bytes,
                                             int32_t length) {
  const int32_t maximum = 4096 * 3 + 3;
  if (length != maximum) return -2;
  const char *original = getenv("HOME");
  if (original == NULL) return -1;
  int32_t size = 0;
  while (size <= maximum && original[size] != '\0') ++size;
  if (size > maximum) return -2;
  memcpy(bytes, original, (size_t)size);
  return size;
}

#include "command_platform_entry.h"
