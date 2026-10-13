// Actual Root/Reader C boundaries. Injected errno/allocation failures are not
// kernel fault observations. Only this fixture's fresh files/descriptors change.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
static const char *injected_detail;
static size_t failure_size;
static int close_failure;
static int close_calls;
static int open_calls;
static void *fixture_malloc(size_t size) {
  return failure_size == size ? NULL : malloc(size);
}
static char *fixture_strerror(int number) {
  return injected_detail == NULL ? NULL : (char *)injected_detail;
}
static int fixture_close(int descriptor) {
  close_calls++;
  int result = close(descriptor);
  if (result == 0 && close_failure != 0) {
    errno = close_failure;
    return -1;
  }
  return result;
}
static int fixture_open(const char *path, int flags, ...) {
  open_calls++;
  return open(path, flags);
}
#define malloc fixture_malloc
#define strerror fixture_strerror
#define close fixture_close
#define open fixture_open
#include "../../src/platform_native/filesystem/filesystem_stub.c"
#undef malloc
#undef strerror
#undef close
#undef open

static int cases;
static void passed(const char *name) { cases++; puts(name); }
static void expect(moonbit_bytes_t bytes, const char *expected) {
  size_t length = strlen(expected);
  assert((size_t)Moonbit_array_length(bytes) == length);
  assert(length == 0 || memcmp(bytes, expected, length) == 0);
  moonbit_decref(bytes);
}
static actql_native_filesystem_root *root_for(const char *path, int ceiling) {
  actql_native_filesystem_root *root =
    actql_native_filesystem_open_root_with_diagnostics(
      (moonbit_bytes_t)path, (int32_t)strlen(path), ceiling);
  assert(actql_native_filesystem_root_ready(root));
  assert(root->diagnostic_ceiling == ceiling);
  return root;
}
static actql_native_filesystem_reader *reader_for(
  actql_native_filesystem_root *root, struct stat status, bool mismatch
) {
  return actql_native_filesystem_open_reader(root, (moonbit_bytes_t)"value.bin", 9,
    (uint64_t)status.st_dev, (uint64_t)status.st_ino + (mismatch ? 1 : 0), status.st_size);
}

int main(void) {
  char *detail = NULL;
  actql_replace_bounded_error(&detail, 4, "abcd");
  expect(actql_copy_diagnostic(detail, 4), "abcd");
  actql_replace_bounded_error(&detail, 4, "abcde");
  expect(actql_copy_diagnostic(detail, 4), "");
  actql_replace_bounded_error(&detail, 4, "\xc3\xa9\xc3\xa9");
  expect(actql_copy_diagnostic(detail, 4), "\xc3\xa9\xc3\xa9");
  actql_replace_bounded_error(&detail, 4, "\xc3\xa9\xc3\xa9x");
  expect(actql_copy_diagnostic(detail, 4), "");
  free(detail); detail = NULL;
  passed("exact/one-over/UTF8 diagnostics: PASS");

  size_t page = (size_t)sysconf(_SC_PAGESIZE);
  char *pages = mmap(NULL, page*2, PROT_READ|PROT_WRITE, MAP_ANON|MAP_PRIVATE, -1, 0);
  assert(pages != MAP_FAILED && mprotect(pages+page, page, PROT_NONE) == 0);
  char *guarded = pages+page-5;
  memset(guarded, 'x', 5);
  actql_replace_bounded_error(&detail, 4, guarded);
  expect(actql_copy_diagnostic(detail, 4), "");
  // Prefix consumes the entire ceiling. Remaining detail bound0 must not
  // fall through to a legacy strlen on the unterminated final page byte.
  injected_detail = pages+page-1;
  actql_replace_bounded_errno_error(&detail, 3, "o", EIO);
  expect(actql_copy_diagnostic(detail, 3), "");
  assert(munmap(pages, page*2) == 0);
  injected_detail = "x";
  actql_replace_bounded_errno_error(&detail, 4, "o", EIO);
  expect(actql_copy_diagnostic(detail, 4), "o: x");
  free(detail); detail = NULL;
  passed("bounded errno scan including remaining0: PASS");

  char path[] = "/private/tmp/actql-reader-diagnostic-XXXXXX";
  assert(mkdtemp(path) != NULL);
  char filename[512];
  assert(snprintf(filename, sizeof(filename), "%s/value.bin", path) > 0);
  int file = open(filename, O_WRONLY|O_CREAT|O_EXCL, 0600);
  assert(file >= 0);
  const char body[] = "abc\xc3\xa9";
  assert(write(file, body, sizeof(body)-1) == (ssize_t)sizeof(body)-1);
  struct stat status;
  assert(fstat(file, &status) == 0 && close(file) == 0);

  for (int ceiling = 0; ceiling <= 20; ceiling += ceiling == 0 ? 1 : 19) {
    actql_native_filesystem_root *root = root_for(path, ceiling);
    actql_native_filesystem_reader *reader = reader_for(root, status, true);
    assert(!actql_native_filesystem_reader_ready(reader));
    assert(reader->diagnostic_ceiling == ceiling);
    assert(actql_native_filesystem_reader_open_failure_kind(reader) == ACTQL_READER_OPEN_GENERATION_MISMATCH);
    expect(actql_native_filesystem_reader_open_error(reader), ceiling == 1 ? "" : "generation mismatch");
    assert(actql_native_filesystem_reader_close(reader) == 0);
    moonbit_decref(reader);
    assert(actql_native_filesystem_root_close(root) == 0);
    moonbit_decref(root);
  }
  passed("generation kind preserved for legacy0/insufficient/exact ceilings: PASS");

  actql_native_filesystem_root *root = root_for(path, 32);
  failure_size = strlen("generation mismatch")+1;
  actql_native_filesystem_reader *reader = reader_for(root, status, true);
  failure_size = 0;
  assert(!actql_native_filesystem_reader_ready(reader));
  assert(actql_native_filesystem_reader_open_failure_kind(reader) == ACTQL_READER_OPEN_GENERATION_MISMATCH);
  expect(actql_native_filesystem_reader_open_error(reader), "");
  assert(actql_native_filesystem_reader_close(reader) == 0);
  moonbit_decref(reader);
  assert(actql_native_filesystem_root_close(root) == 0);
  moonbit_decref(root);
  passed("diagnostic allocation failure cannot change generation kind: PASS");

  root = root_for(path, 4);
  injected_detail = "arbitrarily long diagnostic";
  reader = actql_native_filesystem_open_reader(root, (moonbit_bytes_t)"absent", 6, 0, 0, 0);
  assert(!actql_native_filesystem_reader_ready(reader));
  assert(actql_native_filesystem_reader_open_failure_kind(reader) == ACTQL_READER_OPEN_READ_FAILURE);
  expect(actql_native_filesystem_reader_open_error(reader), "");
  assert(actql_native_filesystem_reader_close(reader) == 0);
  moonbit_decref(reader);
  injected_detail = NULL;
  reader = actql_native_filesystem_open_reader(root, (moonbit_bytes_t)"absent", 6, 0, 0, 0);
  assert(!actql_native_filesystem_reader_ready(reader));
  assert(actql_native_filesystem_reader_open_failure_kind(reader) == ACTQL_READER_OPEN_READ_FAILURE);
  assert(actql_native_filesystem_reader_open_failure_kind(NULL) == ACTQL_READER_OPEN_READ_FAILURE);
  expect(actql_native_filesystem_reader_open_error(reader), "");
  moonbit_decref(reader);
  assert(actql_native_filesystem_root_close(root) == 0);
  moonbit_decref(root);
  passed("oversized/NULL errno detail remains Read refusal: PASS");

  injected_detail = "oversized errno diagnostic";
  actql_native_filesystem_root *failed = actql_native_filesystem_open_root_with_diagnostics(
    (moonbit_bytes_t)filename, (int32_t)strlen(filename), 1);
  assert(!actql_native_filesystem_root_ready(failed));
  expect(actql_native_filesystem_root_error(failed), "");
  moonbit_decref(failed);
  int before = open_calls;
  failed = actql_native_filesystem_open_root_with_diagnostics((moonbit_bytes_t)path, (int32_t)strlen(path), -1);
  assert(!actql_native_filesystem_root_ready(failed) && open_calls == before);
  moonbit_decref(failed);
  passed("omitted Root failure and invalid selection cannot become ready: PASS");

  root = root_for(path, 1);
  reader = reader_for(root, status, false);
  assert(actql_native_filesystem_reader_ready(reader));
  assert(actql_native_filesystem_reader_open_failure_kind(reader) == 0);
  assert(actql_native_filesystem_reader_next(reader, 65536) == 0);
  moonbit_bytes_t bytes = actql_native_filesystem_reader_chunk(reader);
  assert(Moonbit_array_length(bytes) == sizeof(body)-1);
  assert(memcmp(bytes, body, sizeof(body)-1) == 0);
  moonbit_decref(bytes);
  assert(reader->device == (uint64_t)status.st_dev && reader->inode == (uint64_t)status.st_ino && reader->size == status.st_size);
  assert(actql_native_filesystem_reader_finish(reader) == 0);
  assert(actql_native_filesystem_reader_close(reader) == 0);
  moonbit_decref(reader);
  assert(actql_native_filesystem_root_close(root) == 0);
  moonbit_decref(root);
  passed("successful bytes/generation unchanged: PASS");

  root = root_for(path, 1);
  reader = reader_for(root, status, false);
  int original = reader->fd;
  close_calls = 0; close_failure = EIO;
  assert(actql_native_filesystem_reader_close(reader) == -1);
  close_failure = 0;
  assert(reader->fd == -1 && reader->close_result == -1 && close_calls == 1);
  expect(actql_native_filesystem_reader_error(reader), "");
  int replacement = open("/dev/null", O_RDONLY);
  assert(replacement >= 0);
  if (replacement != original) { assert(dup2(replacement, original) == original); assert(close(replacement) == 0); }
  assert(actql_native_filesystem_reader_close(reader) == -1);
  assert(actql_native_filesystem_reader_finish(reader) == -1 && close_calls == 1);
  assert(fcntl(original, F_GETFD) >= 0);
  assert(close(original) == 0);
  // Fixture teardown frees its opaque objects; it is not a product close ACK.
  moonbit_decref(reader);
  assert(actql_native_filesystem_root_close(root) == 0);
  moonbit_decref(root);
  passed("omitted sticky close remains Unknown and never recloses reused FD: PASS");

  root = root_for(path, 8);
  char child_path[512];
  assert(snprintf(child_path, sizeof(child_path), "%s/child", path) > 0);
  assert(mkdir(child_path, 0700) == 0);
  actql_native_filesystem_root *child = actql_native_filesystem_open_child_root(root, (moonbit_bytes_t)"child", 5);
  assert(actql_native_filesystem_root_ready(child) && child->diagnostic_ceiling == 8);
  assert(actql_native_filesystem_root_close(child) == 0); moonbit_decref(child);
  assert(actql_native_filesystem_root_close(root) == 0); moonbit_decref(root);
  assert(rmdir(child_path) == 0);
  passed("original child Root inherits immutable ceiling: PASS");

  assert(unlink(filename) == 0 && rmdir(path) == 0);
  assert(cases == 9);
  printf("Root/Reader diagnostic C cases: %d/9\n", cases);
  return 0;
}
