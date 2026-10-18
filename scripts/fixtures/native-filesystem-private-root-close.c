// Actual private-Root constructor with diagnostic close-failure injection.
// Injected EIO/EINTR are not claims of physical kernel failures.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
static int fixture_close(int);
static int fixture_openat(int, const char *, int, ...);
#define close fixture_close
#define openat fixture_openat
#include "../../src/platform_native/filesystem/filesystem_stub.c"
#undef close
#undef openat
_Noreturn void moonbit_panic(void) { abort(); }
static dev_t selected_device;
static ino_t selected_inode, parent_inode;
static dev_t parent_device;
static int fault_kind, probe_faults;
static int original_fd = -1, close_calls, close_error;
static int fixture_openat(int fd, const char *path, int flags, ...) {
  int result;
  if (flags & O_CREAT) {
    va_list args; va_start(args, flags); int mode = va_arg(args, int); va_end(args);
    result = openat(fd, path, flags, mode);
  } else result = openat(fd, path, flags);
  int saved_errno = errno;
  struct stat st;
  if (original_fd < 0 && result >= 0 && selected_inode &&
      fstat(result, &st) == 0 && st.st_dev == selected_device && st.st_ino == selected_inode)
    original_fd = result;
  errno = saved_errno;
  return result;
}
static int fixture_close(int fd) {
  struct stat st;
  bool probe = false;
  if (probe_faults == 0 && fault_kind && original_fd >= 0 && fstat(fd, &st) == 0) {
    if (fault_kind == 1 && st.st_dev == parent_device && st.st_ino == parent_inode)
      probe = true;
    if (fault_kind == 2 && fd != original_fd &&
        st.st_dev == selected_device && st.st_ino == selected_inode)
      probe = true;
  }
  if (fd == original_fd) close_calls++;
  int result = close(fd);
  if (probe && result == 0) { probe_faults++; errno = EIO; return -1; }
  if (fd == original_fd && fault_kind == 0 && result == 0 && close_error) {
    errno = close_error; return -1;
  }
  return result;
}

static moonbit_bytes_t text(const char *s) {
  size_t n = strlen(s); moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  memcpy(b, s, n); return b;
}
int main(int argc, char **argv) {
  assert(argc == 3);
  const char *selected_case = argv[1], *directory = argv[2];
  bool custody = !strncmp(selected_case, "custody-", 8);
  const char *name = custody ? selected_case + 8 : selected_case;
  bool missing = !strcmp(name, "missing"), current = !strcmp(name, "current-close-eio");
  bool walk = !strcmp(name, "walk-close-eio"), probe = !strcmp(name, "namespace-close-eio");
  bool success = !strcmp(name, "confirmed-private") || current;
  if (walk) fault_kind = 1;
  if (probe) fault_kind = 2;
  char *parent = strdup(directory); assert(parent); char *slash = strrchr(parent, '/');
  assert(slash); *slash = '\0'; struct stat ps; assert(stat(parent, &ps) == 0);
  parent_device = ps.st_dev; parent_inode = ps.st_ino; free(parent);
  if (!missing) {
    assert(chmod(directory, success || walk || probe ? 0700 : 0755) == 0);
    struct stat s; assert(stat(directory, &s) == 0);
    selected_device = s.st_dev; selected_inode = s.st_ino;
  }
  if (!strcmp(name, "privacy-close-eio")) close_error = EIO;
  if (!strcmp(name, "privacy-close-eintr")) close_error = EINTR;
  moonbit_bytes_t path = text(directory);
  actql_native_filesystem_root *root = custody ?
    actql_native_filesystem_open_private_root_with_custody_diagnostics(path, (int32_t)strlen(directory), 128) :
    actql_native_filesystem_open_private_root_with_diagnostics(path, (int32_t)strlen(directory), 128);
  moonbit_decref(path);
  assert(actql_native_filesystem_root_ready(root) == success);
  if (!success && !missing && !walk && !probe) {
    const char *expected = "Host root is not user-owned and private";
    moonbit_bytes_t primary = actql_native_filesystem_root_acquisition_error(root);
    assert(Moonbit_array_length(primary) == (int32_t)strlen(expected));
    assert(memcmp(primary, expected, strlen(expected)) == 0);
    moonbit_decref(primary);
  }
  if (walk || probe || current) {
    assert(custody);
    if (current) {
      assert(close_calls == 0 && root->fd >= 0);
      fault_kind = 2;
      assert(!actql_native_filesystem_private_root_identity(root));
      assert(!actql_native_filesystem_private_root_identity(root));
      assert(probe_faults == 1);
      assert(actql_native_filesystem_root_close(root) == -1);
    }
    assert(root->namespace_cleanup_unconfirmed && probe_faults == 1);
    assert(root->fd == -1 && root->close_result == -1 && close_calls == 1);
    assert(root->namespace_cleanup_error && root->close_error);
    int replacement = open("/dev/null", O_RDONLY); assert(replacement >= 0);
    if (replacement != original_fd) {
      assert(dup2(replacement, original_fd) == original_fd); assert(close(replacement) == 0);
    }
    assert(actql_native_filesystem_root_close(root) == -1);
    assert(close_calls == 1 && fcntl(original_fd, F_GETFD) >= 0);
    assert(close(original_fd) == 0);
  } else if (success) {
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
  printf("{\"case\":\"%s\",\"passed\":true,\"kernelFaultObserved\":false}\n", selected_case);
  return 0;
}
