/* Synthetic-fixture fault only: never used by the product Host. */
#include "moonbit.h"
#include <sys/stat.h>
#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <time.h>

/* Functional expiry only; the Native trusted clock is still authoritative. */
void actql_probe_expiry_wait(void) {
  struct timespec remaining = {.tv_sec = 0, .tv_nsec = 5000000L};
  while (nanosleep(&remaining, &remaining) && errno == EINTR) {}
}

int32_t actql_probe_cleanup_access(moonbit_bytes_t path, int32_t allow) {
  int32_t length = Moonbit_array_length(path);
  if (length < 1 || length > 4096 || memchr(path, 0, (size_t)length)) return 0;
  char name[4097];
  memcpy(name, path, (size_t)length); name[length] = 0;
  struct stat state;
  if (lstat(name, &state) || !S_ISDIR(state.st_mode) || state.st_uid != getuid()) return 0;
  mode_t before = state.st_mode & 0777;
  if (before != (allow ? 0000 : 0700)) return 0;
  return chmod(name, allow ? 0700 : 0000) == 0;
}
