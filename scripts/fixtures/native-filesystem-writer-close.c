// Actual Writer implementation with diagnostic close/fsync fault injection.
// These counters do not claim an actual kernel EIO/EINTR occurrence.
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
static int fixture_fsync(int);
#define close fixture_close
#define fsync fixture_fsync
#include "../../src/platform_native/filesystem/filesystem_stub.c"
#undef close
#undef fsync
static int selected_fd = -1, close_calls, close_error, sync_error;
static bool no_retirement;
static int fixture_close(int fd) {
  if (fd != selected_fd) return close(fd);
  close_calls++;
  if (no_retirement) { errno = close_error; return -1; }
  int result = close(fd);
  if (result == 0 && close_error) { errno = close_error; return -1; }
  return result;
}
static int fixture_fsync(int fd) {
  if (fd == selected_fd && sync_error) { errno = sync_error; return -1; }
  return fsync(fd);
}
static moonbit_bytes_t text(const char *value) {
  size_t n = strlen(value);
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  memcpy(b, value, n); return b;
}
static void writer_fixture(const char *directory,
                           actql_native_filesystem_root *root,
                           actql_native_filesystem_writer *writer) {
  memset(root, 0, sizeof(*root)); memset(writer, 0, sizeof(*writer));
  root->fd = open(directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  assert(root->fd >= 0);
  writer->root = root; writer->staging_name = strdup("stage");
  writer->fd = openat(root->fd, "stage", O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0600);
  assert(writer->fd >= 0); assert(write(writer->fd, "abc", 3) == 3);
  struct stat s; assert(fstat(writer->fd, &s) == 0);
  writer->device = (uint64_t)s.st_dev; writer->inode = (uint64_t)s.st_ino;
  writer->ready = true; writer->staging_present = true;
  writer->max_bytes = writer->written = 3;
  selected_fd = writer->fd; close_calls = close_error = sync_error = 0;
  no_retirement = false;
}
static void release_buffers(actql_native_filesystem_writer *w) {
  free(w->staging_name); free(w->final_name); free(w->error);
  // The new independent close diagnostic is released by the test teardown
  // once its preservation is available; this fixture never finalizes stack roots.
}
static void retry_cannot_finish_unknown(const char *directory, bool from_seal) {
  actql_native_filesystem_root root; actql_native_filesystem_writer w;
  writer_fixture(directory, &root, &w); int original = w.fd;
  close_error = EIO;
  moonbit_bytes_t final = text("object");
  int result = from_seal ? actql_native_filesystem_writer_seal(&w, final, 6)
                         : actql_native_filesystem_writer_cancel(&w);
  assert(result == -1 && close_calls == 1);
  int replacement = open("/dev/null", O_RDONLY);
  assert(replacement >= 0);
  if (replacement != original) { assert(dup2(replacement, original) == original); assert(close(replacement) == 0); }
  assert((from_seal ? actql_native_filesystem_writer_seal(&w, final, 6)
                    : actql_native_filesystem_writer_cancel(&w)) == -1);
  assert(actql_native_filesystem_writer_cancel(&w) == -1);
  assert(close_calls == 1 && fcntl(original, F_GETFD) >= 0);
  struct stat s; assert(fstatat(root.fd, "stage", &s, AT_SYMLINK_NOFOLLOW) == 0);
  assert(fstatat(root.fd, "object", &s, AT_SYMLINK_NOFOLLOW) == -1 && errno == ENOENT);
  assert(close(original) == 0); assert(close(root.fd) == 0);
  moonbit_decref(final); release_buffers(&w);
}
static void interrupted_close_stays_unknown(const char *directory) {
  actql_native_filesystem_root root; actql_native_filesystem_writer w;
  writer_fixture(directory, &root, &w); int original = w.fd;
  close_error = EINTR; no_retirement = true;
  assert(actql_native_filesystem_writer_cancel(&w) == -1);
  assert(actql_native_filesystem_writer_cancel(&w) == -1);
  assert(close_calls == 1 && fcntl(original, F_GETFD) >= 0);
  // Fixture teardown owns this deliberately unretired FD; no product retry.
  assert(close(original) == 0); assert(close(root.fd) == 0); release_buffers(&w);
}
static void sync_failure_is_before_close(const char *directory) {
  actql_native_filesystem_root root; actql_native_filesystem_writer w;
  writer_fixture(directory, &root, &w); sync_error = EIO;
  moonbit_bytes_t final = text("object");
  assert(actql_native_filesystem_writer_seal(&w, final, 6) == -1);
  assert(close_calls == 0 && w.fd == selected_fd);
  sync_error = 0; assert(actql_native_filesystem_writer_cancel(&w) == 0);
  assert(close_calls == 1); assert(close(root.fd) == 0);
  moonbit_decref(final); release_buffers(&w);
}
static void confirmed_seal_is_idempotent(const char *directory) {
  actql_native_filesystem_root root; actql_native_filesystem_writer w;
  writer_fixture(directory, &root, &w); moonbit_bytes_t final = text("object");
  assert(actql_native_filesystem_writer_seal(&w, final, 6) == 0);
  assert(actql_native_filesystem_writer_seal(&w, final, 6) == 0 && close_calls == 1);
  assert(actql_native_filesystem_writer_cancel(&w) == 0 && close_calls == 1);
  assert(close(root.fd) == 0); moonbit_decref(final); release_buffers(&w);
}
static void conflict_preserves_foreign_file(const char *directory) {
  actql_native_filesystem_root root; actql_native_filesystem_writer w;
  writer_fixture(directory, &root, &w);
  int fd = openat(root.fd, "object", O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0600);
  assert(fd >= 0 && write(fd, "different", 9) == 9 && close(fd) == 0);
  moonbit_bytes_t final = text("object");
  assert(actql_native_filesystem_writer_seal(&w, final, 6) == 1);
  assert(actql_native_filesystem_writer_cancel(&w) == 0 && close_calls == 1);
  char bytes[9]; fd = openat(root.fd, "object", O_RDONLY | O_CLOEXEC);
  assert(fd >= 0 && read(fd, bytes, 9) == 9 && memcmp(bytes, "different", 9) == 0);
  assert(close(fd) == 0 && close(root.fd) == 0);
  moonbit_decref(final); release_buffers(&w);
}
int main(int argc, char **argv) {
  assert(argc == 3);
  if (!strcmp(argv[1], "seal-close-eio")) retry_cannot_finish_unknown(argv[2], true);
  else if (!strcmp(argv[1], "cancel-close-eio")) retry_cannot_finish_unknown(argv[2], false);
  else if (!strcmp(argv[1], "cancel-close-eintr")) interrupted_close_stays_unknown(argv[2]);
  else if (!strcmp(argv[1], "sync-before-close")) sync_failure_is_before_close(argv[2]);
  else if (!strcmp(argv[1], "confirmed-seal")) confirmed_seal_is_idempotent(argv[2]);
  else if (!strcmp(argv[1], "foreign-conflict")) conflict_preserves_foreign_file(argv[2]);
  else assert(false);
  printf("{\"case\":\"%s\",\"passed\":true,\"kernelFaultObserved\":false}\n", argv[1]); return 0;
}
