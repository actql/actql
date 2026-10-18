#include "moonbit.h"

#include <stdint.h>
#include <stdbool.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
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
