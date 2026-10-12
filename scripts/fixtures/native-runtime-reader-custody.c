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
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#ifndef __APPLE__
#include <dlfcn.h>
#endif

static int fixture_kind(int descriptor) {
  const char *root = getenv("ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT");
  if (root == NULL || root[0] != '/') return 0;
  int flags = fcntl(descriptor, F_GETFL);
  if (flags < 0 || (flags & O_ACCMODE) != O_RDONLY) return 0;
  char path[PATH_MAX];
#ifdef __APPLE__
  if (fcntl(descriptor, F_GETPATH, path) != 0) return 0;
#else
  char proc_path[64];
  int proc_length = snprintf(proc_path, sizeof(proc_path), "/proc/self/fd/%d", descriptor);
  if (proc_length < 0 || (size_t)proc_length >= sizeof(proc_path)) return 0;
  ssize_t path_length = readlink(proc_path, path, sizeof(path) - 1);
  if (path_length < 0 || (size_t)path_length >= sizeof(path) - 1) return 0;
  path[path_length] = '\0';
#endif
  char expected[PATH_MAX];
  int length = snprintf(expected, sizeof(expected),
    "%s/runtime-constructor-pending/local-runtime.json", root);
  if (length < 0 || (size_t)length >= sizeof(expected)) return 0;
  if (strcmp(path, expected) == 0) return 1;
  length = snprintf(expected, sizeof(expected),
    "%s/runtime-constructor-acked/local-runtime.json", root);
  if (length < 0 || (size_t)length >= sizeof(expected)) return 0;
  return strcmp(path, expected) == 0 ? 2 : 0;
}

#ifdef __APPLE__
#define original_fstat fstat
#define original_close close
#else
static int original_fstat(int descriptor, struct stat *status) {
  int (*actual)(int, struct stat *) = dlsym(RTLD_NEXT, "fstat");
  if (actual == NULL) { errno = ENOSYS; return -1; }
  return actual(descriptor, status);
}
static int original_close(int descriptor) {
  int (*actual)(int) = dlsym(RTLD_NEXT, "close");
  if (actual == NULL) { errno = ENOSYS; return -1; }
  return actual(descriptor);
}
#endif

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
