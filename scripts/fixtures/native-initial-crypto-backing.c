// Actual private backing implementation with diagnostic syscall faults. These
// counters do not claim a kernel EINTR/EIO, a Crypto domain or installed init.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static int fixture_fstat(int, struct stat *);
static int fixture_close(int);
static int fixture_mkstemp(char *);
static int fixture_ftruncate(int, off_t);
#define fstat fixture_fstat
#define close fixture_close
#define mkstemp fixture_mkstemp
#define ftruncate fixture_ftruncate
#include "../../src/cmd/native_client/initial_crypto_backing_stub.c"
#undef fstat
#undef close
#undef mkstemp
#undef ftruncate
_Noreturn void moonbit_panic(void) { abort(); }
static int first_stat_fault, close_fault, original_fd = -1;
static int open_calls, truncate_calls, close_calls;
static int fixture_mkstemp(char *path) {
  open_calls++;
  return mkstemp(path);
}
static int fixture_ftruncate(int fd, off_t bytes) {
  truncate_calls++;
  return ftruncate(fd, bytes);
}
static int fixture_fstat(int fd, struct stat *actual) {
  if (first_stat_fault) {
    first_stat_fault = 0;
    original_fd = fd;
    errno = EINTR;
    return -1;
  }
  return fstat(fd, actual);
}
static int fixture_close(int fd) {
  close_calls++;
  int result = close(fd);
  if (result == 0 && close_fault) { errno = EIO; return -1; }
  return result;
}
static void interrupted_initial_stat(void) {
  first_stat_fault = 1;
  actql_initial_crypto_backing *value = actql_initial_crypto_backing_open(16384);
  assert(value && !value->ready && value->fd == original_fd && value->name_present);
  fprintf(stderr, "retained original partial backing: %s\n", value->name);
  assert(open_calls == 1 && truncate_calls == 0 && close_calls == 0);
  assert(actql_initial_crypto_backing_acquisition_issue(value) == EINTR);
  assert(!value->identity_observed && !value->descriptor_exposed);
  assert(actql_initial_crypto_backing_descriptor(value) == -1);
  assert(actql_initial_crypto_backing_close(value) == 1);
  assert(actql_initial_crypto_backing_close(value) == 1);
  assert(close_calls == 1 && open_calls == 1 && truncate_calls == 0);
  assert(actql_initial_crypto_backing_acquisition_issue(value) == EINTR);
  assert(!actql_initial_crypto_backing_current(value));
  assert(fcntl(original_fd, F_GETFD) == -1 && errno == EBADF);
  struct stat actual;
  assert(lstat(value->name, &actual) == -1 && errno == ENOENT);
  moonbit_decref(value);
}
static void consumed_close_unknown(void) {
  actql_initial_crypto_backing *value = actql_initial_crypto_backing_open(16384);
  assert(value && actql_initial_crypto_backing_current(value));
  int original = actql_initial_crypto_backing_descriptor(value);
  assert(original >= 0);
  close_fault = 1;
  assert(actql_initial_crypto_backing_close(value) == 0 && close_calls == 1);
  int replacement = open("/dev/null", O_RDONLY);
  assert(replacement >= 0);
  if (replacement != original) {
    assert(dup2(replacement, original) == original);
    assert(close(replacement) == 0);
  }
  assert(actql_initial_crypto_backing_close(value) == 0);
  assert(close_calls == 1 && fcntl(original, F_GETFD) >= 0);
  assert(actql_initial_crypto_backing_descriptor(value) == -1);
  moonbit_decref(value);
  assert(close_calls == 1 && fcntl(original, F_GETFD) >= 0);
  assert(close(original) == 0);
}
int main(int argc, char **argv) {
  assert(argc == 2);
  if (!strcmp(argv[1], "interrupted-initial-stat")) interrupted_initial_stat();
  else if (!strcmp(argv[1], "consumed-close-unknown")) consumed_close_unknown();
  else abort();
  printf("{\"case\":\"%s\",\"passed\":true,\"kernelFaultObserved\":false}\n", argv[1]);
  return 0;
}
