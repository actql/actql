#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <time.h>

void actql_native_remote_transfer_reconciliation_wait(int milliseconds) {
  if (milliseconds <= 0) {
    return;
  }
  struct timespec remaining = {
    .tv_sec = milliseconds / 1000,
    .tv_nsec = (long)(milliseconds % 1000) * 1000000L,
  };
  while (nanosleep(&remaining, &remaining) != 0 && errno == EINTR) {
  }
}
