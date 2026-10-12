// Focused FFI counterexamples, compiled against the actual Reader implementation.
// Diagnostic injection is not an actual kernel EIO/EINTR observation. This
// standalone fixture has no other thread sharing the Reader or integer FD.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int fixture_close(int descriptor);
#define close fixture_close
#include "../../src/platform_native/filesystem/filesystem_stub.c"
#undef close

static int close_calls;
static int injected_errno;
static bool injected_without_retirement;

static int fixture_close(int descriptor) {
  close_calls += 1;
  if (injected_without_retirement) {
    errno = injected_errno;
    return -1;
  }
  int result = close(descriptor);
  if (result == 0 && injected_errno != 0) {
    errno = injected_errno;
    return -1;
  }
  return result;
}

static actql_native_filesystem_reader fixture_reader(FILE *file) {
  int descriptor = dup(fileno(file));
  assert(descriptor >= 0);
  struct stat status;
  assert(fstat(descriptor, &status) == 0);
  actql_native_filesystem_reader reader = {0};
  reader.fd = descriptor;
  reader.ready = true;
  reader.device = (uint64_t)status.st_dev;
  reader.inode = (uint64_t)status.st_ino;
  reader.size = (int64_t)status.st_size;
  reader.offset = reader.size;
  close_calls = 0;
  injected_errno = 0;
  injected_without_retirement = false;
  return reader;
}

static void release_fixture_buffers(actql_native_filesystem_reader *reader) {
  free(reader->error);
  free(reader->close_error);
  free(reader->chunk);
}

static void error_survives_reused_descriptor(bool from_finish) {
  FILE *file = tmpfile();
  assert(file != NULL);
  actql_native_filesystem_reader reader = fixture_reader(file);
  int original = reader.fd;
  injected_errno = EIO;
  int result = from_finish ? actql_native_filesystem_reader_finish(&reader)
                          : actql_native_filesystem_reader_close(&reader);
  assert(result == -1);
  assert(close_calls == 1);
  char diagnostic[256];
  assert(reader.close_error != NULL);
  snprintf(diagnostic, sizeof(diagnostic), "%s", reader.close_error);
  // Only fixture-owned descriptors are present in this single-threaded scope.
  int replacement = open("/dev/null", O_RDONLY);
  assert(replacement >= 0);
  if (replacement != original) {
    assert(dup2(replacement, original) == original);
    assert(close(replacement) == 0);
  }
  assert(actql_native_filesystem_reader_close(&reader) == -1);
  assert(actql_native_filesystem_reader_finish(&reader) == -1);
  assert(actql_native_filesystem_reader_next(&reader, 1) == 2);
  assert(close_calls == 1);
  assert(strcmp(diagnostic, reader.close_error) == 0);
  assert(fcntl(original, F_GETFD) >= 0);
  unsigned char byte;
  assert(read(original, &byte, 1) == 0);
  assert(close(original) == 0);
  release_fixture_buffers(&reader);
  assert(fclose(file) == 0);
}

static void ambiguous_outcome_is_not_acknowledged(void) {
  FILE *file = tmpfile();
  assert(file != NULL);
  actql_native_filesystem_reader reader = fixture_reader(file);
  int original = reader.fd;
  injected_errno = EINTR;
  injected_without_retirement = true;
  assert(actql_native_filesystem_reader_finish(&reader) == -1);
  assert(actql_native_filesystem_reader_close(&reader) == -1);
  assert(actql_native_filesystem_reader_finish(&reader) == -1);
  assert(close_calls == 1);
  assert(reader.close_result == -1);
  assert(fcntl(original, F_GETFD) >= 0);
  // Fixture teardown is not product recovery or an acknowledgement issued by
  // Reader. It owns the injected still-open descriptor and performs no retry.
  assert(close(original) == 0);
  release_fixture_buffers(&reader);
  assert(fclose(file) == 0);
}

static void pre_close_failure_keeps_first_close_available(void) {
  FILE *file = tmpfile();
  assert(file != NULL);
  assert(fwrite("abc", 1, 3, file) == 3);
  assert(fflush(file) == 0);
  actql_native_filesystem_reader reader = fixture_reader(file);
  reader.offset = 1;
  assert(actql_native_filesystem_reader_finish(&reader) == 2);
  assert(close_calls == 0);
  assert(actql_native_filesystem_reader_close(&reader) == 0);
  assert(close_calls == 1);
  assert(actql_native_filesystem_reader_finish(&reader) == 3);
  assert(actql_native_filesystem_reader_close(&reader) == 0);
  assert(close_calls == 1);
  release_fixture_buffers(&reader);
  assert(fclose(file) == 0);
}

static void generation_refusal_keeps_first_close_available(void) {
  FILE *file = tmpfile();
  assert(file != NULL);
  actql_native_filesystem_reader reader = fixture_reader(file);
  reader.inode += 1;
  assert(actql_native_filesystem_reader_finish(&reader) == 1);
  assert(close_calls == 0);
  assert(actql_native_filesystem_reader_close(&reader) == 0);
  assert(close_calls == 1);
  assert(actql_native_filesystem_reader_finish(&reader) == 3);
  release_fixture_buffers(&reader);
  assert(fclose(file) == 0);
}

static void acknowledged_finish_is_idempotent(void) {
  FILE *file = tmpfile();
  assert(file != NULL);
  assert(fwrite("abc", 1, 3, file) == 3);
  assert(fflush(file) == 0);
  assert(fseek(file, 0, SEEK_SET) == 0);
  actql_native_filesystem_reader reader = fixture_reader(file);
  reader.offset = 0;
  // Physical next completes before finish; no concurrent I/O is fabricated.
  assert(actql_native_filesystem_reader_next(&reader, 3) == 0);
  assert(reader.chunk_length == 3);
  assert(memcmp(reader.chunk, "abc", 3) == 0);
  assert(actql_native_filesystem_reader_finish(&reader) == 0);
  assert(actql_native_filesystem_reader_finish(&reader) == 0);
  assert(actql_native_filesystem_reader_close(&reader) == 0);
  assert(close_calls == 1);
  release_fixture_buffers(&reader);
  assert(fclose(file) == 0);
}

static void root_close_preserves_diagnostic_and_replacement(void) {
  actql_native_filesystem_root root = {0};
  root.fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  assert(root.fd >= 0);
  int original = root.fd;
  injected_errno = EIO;
  injected_without_retirement = false;
  close_calls = 0;
  assert(actql_native_filesystem_root_close(&root) == -1);
  assert(close_calls == 1);
  assert(root.close_error != NULL);
  char diagnostic[256];
  snprintf(diagnostic, sizeof(diagnostic), "%s", root.close_error);
  int replacement = open("/dev/null", O_RDONLY);
  assert(replacement >= 0);
  if (replacement != original) {
    assert(dup2(replacement, original) == original);
    assert(close(replacement) == 0);
  }
  // Another operation's diagnostic cannot overwrite the original close fact.
  actql_replace_error(&root.error, "another operation failed");
  assert(actql_native_filesystem_root_close(&root) == -1);
  assert(close_calls == 1);
  assert(strcmp(diagnostic, root.close_error) == 0);
  assert(fcntl(original, F_GETFD) >= 0);
  assert(close(original) == 0);
  free(root.error);
  free(root.close_error);
}

static void root_acknowledgement_does_not_stop_child_reader(void) {
  FILE *file = tmpfile();
  assert(file != NULL);
  assert(fwrite("abc", 1, 3, file) == 3);
  assert(fflush(file) == 0);
  assert(fseek(file, 0, SEEK_SET) == 0);
  actql_native_filesystem_reader reader = fixture_reader(file);
  reader.offset = 0;
  actql_native_filesystem_root root = {0};
  root.fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  assert(root.fd >= 0);
  assert(actql_native_filesystem_root_close(&root) == 0);
  assert(actql_native_filesystem_root_close(&root) == 0);
  assert(close_calls == 1);
  assert(actql_native_filesystem_reader_next(&reader, 3) == 0);
  assert(memcmp(reader.chunk, "abc", 3) == 0);
  assert(actql_native_filesystem_reader_finish(&reader) == 0);
  assert(close_calls == 2);
  release_fixture_buffers(&reader);
  assert(fclose(file) == 0);
}

int main(void) {
  error_survives_reused_descriptor(false);
  error_survives_reused_descriptor(true);
  ambiguous_outcome_is_not_acknowledged();
  pre_close_failure_keeps_first_close_available();
  generation_refusal_keeps_first_close_available();
  acknowledged_finish_is_idempotent();
  root_close_preserves_diagnostic_and_replacement();
  root_acknowledgement_does_not_stop_child_reader();
  puts("Reader/root FFI focused counterexamples: 8/8");
  return 0;
}
