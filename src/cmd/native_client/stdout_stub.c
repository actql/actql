#include "moonbit.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <time.h>

int32_t actql_native_client_write_stdout(moonbit_bytes_t bytes, int32_t length) {
  if (length < 0) return 0;
  if (fwrite(bytes, 1, (size_t)length, stdout) != (size_t)length) return 0;
  return fflush(stdout) == 0;
}

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
