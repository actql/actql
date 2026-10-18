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
// preargument constructor may borrow it without a Moon String allocation. The
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

// The OS argv and launcher marker stay in their original process lifetime.
// This private observation performs no managed copy or physical acquisition.
// Once selected or refused it cannot restart against changed process inputs.
static bool actql_command_input_attempted;
static int actql_command_input_status = ACTQL_COMMAND_INPUT_INVALID;
static const char *actql_command_input_source;
static const char *actql_command_input_context;
static actql_bootstrap_command_preparation_observation actql_command_input;

int32_t actql_native_client_measure_prearguments(
    int32_t maximum_arguments, int32_t maximum_argument_bytes,
    int32_t maximum_storage_bytes, int32_t maximum_context_bytes) {
  if (actql_command_input_attempted) return actql_command_input_status;
  actql_command_input_attempted = true;
  const char *context = getenv("ACTQL_NATIVE_LOCAL_RUNTIME");
  if (context == NULL) {
    actql_command_input_status = ACTQL_COMMAND_INPUT_NOT_SELECTED;
    return actql_command_input_status;
  }
  if (maximum_arguments <= 0 || maximum_argument_bytes <= 0 ||
      maximum_storage_bytes <= 0 || maximum_context_bytes <= 0)
    return actql_command_input_status;
#if defined(__APPLE__)
  const char *source = actql_native_client_selected_source();
  actql_command_input_status = actql_bootstrap_measure_command_preparation(
      source, context, *_NSGetArgc(), (const char *const *)*_NSGetArgv(),
      (size_t)maximum_arguments, (size_t)maximum_argument_bytes,
      (size_t)maximum_storage_bytes, (size_t)maximum_context_bytes,
      &actql_command_input);
  if (actql_command_input_status == ACTQL_COMMAND_INPUT_OK) {
    actql_command_input_source = source;
    actql_command_input_context = context;
  }
#endif
  return actql_command_input_status;
}

int32_t actql_native_client_preargument_count(void) {
  return actql_command_input_status == ACTQL_COMMAND_INPUT_OK
      ? (int32_t)actql_command_input.input.arguments : -1;
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
