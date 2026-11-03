// Test-only diagnostic injection for the exact owned fixture paths.
// This retires a real FD before reporting EIO; it does not observe kernel EIO.
#define _DARWIN_C_SOURCE
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>
#ifndef __APPLE__
#include <dlfcn.h>
#endif

static char pending_path[PATH_MAX];
static char acked_path[PATH_MAX];
static bool fixture_ready;

#ifdef __APPLE__
#define original_fstat fstat
#define original_close close
#else
static int (*actual_fstat)(int, struct stat *);
static int (*actual_close)(int);

static int original_fstat(int descriptor, struct stat *status) {
  if (actual_fstat == NULL) _exit(125);
  return actual_fstat(descriptor, status);
}
static int original_close(int descriptor) {
  if (actual_close == NULL) _exit(125);
  return actual_close(descriptor);
}
#endif

// Capture this exec's fixed fixture scope before any test or compiler spawn.
// close can be entered while a spawn performs descriptor actions; it must not
// consult the environment, resolve symbols or format paths at that boundary.
__attribute__((constructor)) static void capture_fixture(void) {
#ifndef __APPLE__
  actual_close = dlsym(RTLD_NEXT, "close");
  actual_fstat = dlsym(RTLD_NEXT, "fstat");
  if (actual_close == NULL || actual_fstat == NULL) _exit(125);
#endif
  const char *root = getenv("ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT");
  if (root == NULL || root[0] != '/') _exit(125);
  int length = snprintf(pending_path, sizeof(pending_path),
    "%s/runtime-constructor-pending/local-runtime.json", root);
  if (length < 0 || (size_t)length >= sizeof(pending_path)) _exit(125);
  length = snprintf(acked_path, sizeof(acked_path),
    "%s/runtime-constructor-acked/local-runtime.json", root);
  if (length < 0 || (size_t)length >= sizeof(acked_path)) _exit(125);
  fixture_ready = true;
}

static bool same_path(const char *actual, const char *expected) {
  while (*actual == *expected) {
    if (*actual == '\0') return true;
    actual++;
    expected++;
  }
  return false;
}

static int fixture_kind(int descriptor) {
  if (!fixture_ready) return 0;
  int flags = fcntl(descriptor, F_GETFL);
  if (flags < 0 || (flags & O_ACCMODE) != O_RDONLY) return 0;
  char path[PATH_MAX];
#ifdef __APPLE__
  if (fcntl(descriptor, F_GETPATH, path) != 0) return 0;
#else
  char proc_path[64] = "/proc/self/fd/";
  char digits[3 * sizeof(int) + 1];
  size_t count = 0, position = sizeof("/proc/self/fd/") - 1;
  unsigned int value = (unsigned int)descriptor;
  do {
    digits[count++] = (char)('0' + value % 10);
    value /= 10;
  } while (value != 0);
  while (count != 0) proc_path[position++] = digits[--count];
  proc_path[position] = '\0';
  ssize_t path_length = readlink(proc_path, path, sizeof(path) - 1);
  if (path_length < 0 || (size_t)path_length >= sizeof(path) - 1) return 0;
  path[path_length] = '\0';
#endif
  if (same_path(path, pending_path)) return 1;
  return same_path(path, acked_path) ? 2 : 0;
}

static int fixture_fstat(int descriptor, struct stat *status) {
  int result = original_fstat(descriptor, status);
  if (result == 0 && S_ISREG(status->st_mode) && fixture_kind(descriptor) != 0) {
    errno = EIO;
    return -1;
  }
  return result;
}

static int fixture_close(int descriptor) {
  int kind = fixture_kind(descriptor);
  int result = original_close(descriptor);
  if (kind == 1 && result == 0) {
    errno = EIO;
    return -1;
  }
  return result;
}

#ifdef __APPLE__
#define INTERPOSE(replacement, original) \
  __attribute__((used)) static struct { const void *new_fn; const void *old_fn; } \
  interpose_##original __attribute__((section("__DATA,__interpose"))) = { \
    (const void *)&replacement, (const void *)&original }
INTERPOSE(fixture_fstat, fstat);
INTERPOSE(fixture_close, close);
#else
int fstat(int descriptor, struct stat *status) { return fixture_fstat(descriptor, status); }
int close(int descriptor) { return fixture_close(descriptor); }
#endif
