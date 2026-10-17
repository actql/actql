// Actual private-Root constructor with diagnostic close-failure injection.
// Injected EIO/EINTR are not claims of physical kernel failures.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static int fixture_close(int);
#define close fixture_close
#include "../../src/platform_native/filesystem/filesystem_stub.c"
#undef close
_Noreturn void moonbit_panic(void) { abort(); }
static dev_t selected_device;
static ino_t selected_inode;
static int original_fd = -1, close_calls, close_error;
static int fixture_close(int fd) {
  struct stat s;
  if (selected_inode && fstat(fd, &s) == 0 &&
      s.st_dev == selected_device && s.st_ino == selected_inode) {
    original_fd = fd; close_calls++;
    int result = close(fd);
    if (result == 0 && close_error) { errno = close_error; return -1; }
    return result;
  }
  return close(fd);
}
static moonbit_bytes_t text(const char *s) {
  size_t n = strlen(s); moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  memcpy(b, s, n); return b;
}
int main(int argc, char **argv) {
  assert(argc == 3);
  const char *name = argv[1], *directory = argv[2];
  bool missing = !strcmp(name, "missing"), success = !strcmp(name, "confirmed-private");
  if (!missing) {
    assert(chmod(directory, success ? 0700 : 0755) == 0);
    struct stat s; assert(stat(directory, &s) == 0);
    selected_device = s.st_dev; selected_inode = s.st_ino;
  }
  if (!strcmp(name, "privacy-close-eio")) close_error = EIO;
  if (!strcmp(name, "privacy-close-eintr")) close_error = EINTR;
  moonbit_bytes_t path = text(directory);
  actql_native_filesystem_root *root =
    actql_native_filesystem_open_private_root_with_diagnostics(path, (int32_t)strlen(directory), 128);
  moonbit_decref(path);
  assert(actql_native_filesystem_root_ready(root) == success);
  if (success) {
    assert(close_calls == 0 && root->fd >= 0);
    assert(actql_native_filesystem_root_close(root) == 0);
    assert(actql_native_filesystem_root_close(root) == 0 && close_calls == 1);
  } else if (!close_error) {
    // No acquired FD, or the constructor's own confirmed rejection cleanup.
    assert(root->fd == -1);
    assert(actql_native_filesystem_root_close(root) == 0);
    assert(actql_native_filesystem_root_close(root) == 0);
    assert(close_calls == (missing ? 0 : 1));
  } else {
    assert(root->error && root->close_error && root->close_result == -1);
    assert(root->fd == -1 && close_calls == 1);
    int replacement = open("/dev/null", O_RDONLY); assert(replacement >= 0);
    if (replacement != original_fd) {
      assert(dup2(replacement, original_fd) == original_fd); assert(close(replacement) == 0);
    }
    assert(actql_native_filesystem_root_close(root) == -1);
    assert(actql_native_filesystem_root_close(root) == -1);
    assert(close_calls == 1 && fcntl(original_fd, F_GETFD) >= 0);
    // Fixture teardown owns only this replacement, never a product retry.
    assert(close(original_fd) == 0);
  }
  moonbit_decref(root);
  printf("{\"case\":\"%s\",\"passed\":true,\"kernelFaultObserved\":false}\n", name);
  return 0;
}
