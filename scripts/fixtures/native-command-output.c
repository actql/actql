#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

static int calls;
static int failure_call;
static int status_without_binding;
static int selected_setvbuf(FILE *stream, char *buffer, int mode, size_t length) {
  ++calls;
  if (calls == failure_call) { errno = EIO; return 23; }
  if (status_without_binding) return 0;
  return setvbuf(stream, buffer, mode, length);
}

/* Faults affect only this fixture's call into the actual private helper. The
 * successful path still binds real libc FILEs to their original buffers. */
#define setvbuf selected_setvbuf
#include "../../src/cmd/native_client/command_output.h"
#undef setvbuf

int main(int argc, char **argv) {
  assert(argc == 2);
  FILE *output = tmpfile(), *error = tmpfile();
  assert(output && error && output != error);
  actql_bootstrap_command_output original = {0};
  if (strcmp(argv[1], "invalid") == 0) {
    assert(!actql_bootstrap_bind_command_output(NULL, output, error));
    assert(!actql_bootstrap_bind_command_output(&original, NULL, error));
    assert(!actql_bootstrap_bind_command_output(&original, output, output));
    assert(!original.attempted && calls == 0);
  } else if (strcmp(argv[1], "first-failed") == 0) {
    failure_call = 1;
    assert(!actql_bootstrap_bind_command_output(&original, output, error));
    assert(original.attempted && original.output_result == 23);
    assert(original.output_errno == EIO);
    assert(!original.output_configured && !original.error_attempted);
    assert(original.output == output && original.error == error);
    assert(!actql_bootstrap_bind_command_output(&original, output, error));
    assert(calls == 1);
  } else if (strcmp(argv[1], "second-failed") == 0) {
    failure_call = 2;
    assert(!actql_bootstrap_bind_command_output(&original, output, error));
    assert(original.attempted && original.output_result == 0);
    assert(original.output_configured && original.error_attempted);
    assert(original.error_result == 23 && !original.error_configured);
    assert(original.error_errno == EIO);
    assert(actql_bootstrap_output_buffer_current(output,
      original.output_buffer, sizeof(original.output_buffer)));
    assert(!actql_bootstrap_command_output_current(&original, output, error));
    assert(!actql_bootstrap_bind_command_output(&original, output, error));
    assert(calls == 2);
    assert(original.error_result == 23 && original.error_errno == EIO);
    /* A partial second setup cannot discard the first actual binding. Its
     * original FILE can still acknowledge its own output before fclose. */
    assert(fwrite("original", 1, 8, output) == 8);
    assert(fflush(output) == 0);
  } else if (strcmp(argv[1], "status-only") == 0) {
    status_without_binding = 1;
    assert(!actql_bootstrap_bind_command_output(&original, output, error));
    assert(original.output_result == 0 && original.output_configured);
    assert(!original.error_attempted && calls == 1);
    assert(!actql_bootstrap_command_output_current(&original, output, error));
  } else {
    assert(strcmp(argv[1], "original") == 0 ||
      strcmp(argv[1], "changed-buffer") == 0);
    assert(actql_bootstrap_bind_command_output(&original, output, error));
    assert(calls == 2);
    assert(actql_bootstrap_command_output_current(&original, output, error));
    assert(!actql_bootstrap_command_output_current(&original, error, output));
    assert(!actql_bootstrap_bind_command_output(&original, output, error));
    assert(calls == 2);
    if (strcmp(argv[1], "changed-buffer") == 0) {
      /* The same FILE identity and earlier success cannot hide replacement
       * backing. Keep both original buffers and refuse a replacement setup. */
      static char replacement[4096];
      assert(setvbuf(output, replacement, _IOFBF, sizeof(replacement)) == 0);
      assert(!actql_bootstrap_command_output_current(&original, output, error));
      assert(!actql_bootstrap_bind_command_output(&original, output, error));
      assert(calls == 2);
    } else {
      unsigned char bytes[10003], observed[10003];
      for (size_t index = 0; index < sizeof(bytes); ++index)
        bytes[index] = (unsigned char)(index % 251);
      assert(fwrite(bytes, 1, sizeof(bytes), output) == sizeof(bytes));
      assert(fflush(output) == 0);
      assert(fwrite(bytes, 1, sizeof(bytes), error) == sizeof(bytes));
      assert(fflush(error) == 0);
      assert(actql_bootstrap_command_output_current(&original, output, error));
      rewind(output);
      assert(fread(observed, 1, sizeof(observed), output) == sizeof(observed));
      assert(memcmp(bytes, observed, sizeof(bytes)) == 0);
      rewind(error);
      assert(fread(observed, 1, sizeof(observed), error) == sizeof(observed));
      assert(memcmp(bytes, observed, sizeof(bytes)) == 0);
    }
  }
  /* These FILEs are owned solely by this fixture. Buffers stay alive until the
   * actual fclose results; helper status never substitutes for those results. */
  assert(fclose(output) == 0);
  assert(fclose(error) == 0);
  puts("original command output binding passed");
  return 0;
}
