// Actual same Writer constructor/close boundary. Faults are diagnostic counters,
// not claims about a kernel EIO or an installed signing capability.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <sys/stat.h>
static int fixture_fstat(int, struct stat *);
#define fstat fixture_fstat
#define main original_writer_close_fixture_main
#include "native-filesystem-writer-close.c"
#undef main
#undef fstat
static bool reject_inspection;
static int fixture_fstat(int fd, struct stat *s) {
  if (reject_inspection) {
    selected_fd = fd; errno = EIO; return -1;
  }
  return fstat(fd, s);
}
static void retained_writer(const char *directory, bool unknown) {
  actql_native_filesystem_root root; actql_native_filesystem_writer w;
  writer_fixture(directory, &root, &w); int original = w.fd;
  close_error = unknown ? EIO : 0;
  assert(actql_native_filesystem_writer_close_retaining_files(&w) == (unknown ? -1 : 0));
  assert(w.preserve_names && w.cleanup_requested && close_calls == 1);
  assert(actql_native_filesystem_writer_close_retaining_files(&w) == (unknown ? -1 : 0));
  assert(close_calls == 1 && fcntl(original, F_GETFD) == -1 && errno == EBADF);
  moonbit_bytes_t final = text("object"), body = text("x");
  assert(actql_native_filesystem_writer_append(&w, body, 1) == 2);
  assert(actql_native_filesystem_writer_seal(&w, final, 6) == (unknown ? -1 : 3));
  assert(actql_native_filesystem_writer_pending_cleanup(&w) == 1);
  if (unknown) assert(actql_native_filesystem_writer_cancel(&w) == -1);
  struct stat s; assert(fstatat(root.fd, "stage", &s, AT_SYMLINK_NOFOLLOW) == 0 && s.st_size == 3);
  assert(fstatat(root.fd, "object", &s, AT_SYMLINK_NOFOLLOW) < 0 && errno == ENOENT);
  assert(close(root.fd) == 0); moonbit_decref(final); moonbit_decref(body); release_buffers(&w);
}
static void rejected_constructor(const char *directory, bool unknown) {
  moonbit_bytes_t path = text(directory), stage = text("rejected");
  actql_native_filesystem_root *root = actql_native_filesystem_open_root(path, (int32_t)strlen(directory));
  assert(root->fd >= 0); reject_inspection = true;
  actql_native_filesystem_writer *writer = actql_native_filesystem_create_writer(root, stage, 8, 119);
  reject_inspection = false;
  assert(!writer->ready && writer->preserve_names && writer->fd >= 0);
  assert(strstr(writer->error, "inspect staging file") != NULL);
  assert(actql_native_filesystem_writer_pending_cleanup(writer) == 1);
  int original = writer->fd; close_calls = 0; close_error = unknown ? EIO : 0;
  assert(actql_native_filesystem_writer_close_retaining_files(writer) == (unknown ? -1 : 0));
  assert(actql_native_filesystem_writer_close_retaining_files(writer) == (unknown ? -1 : 0));
  assert(close_calls == 1 && fcntl(original, F_GETFD) < 0 && errno == EBADF);
  if (unknown) {
    assert(actql_native_filesystem_writer_pending_cleanup(writer) == 1);
    assert(actql_native_filesystem_writer_cancel(writer) == -1);
  }
  moonbit_decref(writer);
  struct stat s; assert(fstatat(root->fd, "rejected", &s, AT_SYMLINK_NOFOLLOW) == 0 && s.st_size == 0);
  assert(close_calls == 1 && actql_native_filesystem_root_close(root) == 0);
  moonbit_decref(root); moonbit_decref(path); moonbit_decref(stage);
}
int main(int argc, char **argv) {
  assert(argc == 3);
  if (!strcmp(argv[1], "retained-close")) retained_writer(argv[2], false);
  else if (!strcmp(argv[1], "retained-unknown")) retained_writer(argv[2], true);
  else if (!strcmp(argv[1], "rejected-constructor")) rejected_constructor(argv[2], false);
  else if (!strcmp(argv[1], "rejected-close-unknown")) rejected_constructor(argv[2], true);
  else assert(false);
  printf("{\"case\":\"%s\",\"passed\":true,\"kernelFaultObserved\":false}\n", argv[1]);
  return 0;
}
