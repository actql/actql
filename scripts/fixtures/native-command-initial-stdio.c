#include <assert.h>
#include <stdio.h>
#include <string.h>

static int setup_calls;
static int selected_setvbuf(FILE *stream, char *buffer, int mode, size_t bytes) {
  ++setup_calls;
  return setvbuf(stream, buffer, mode, bytes);
}
#define setvbuf selected_setvbuf
#include "../../src/cmd/native_client/command_initial_stdio.h"
#undef setvbuf

static actql_bootstrap_command_stdio streams;
static actql_bootstrap_command_output buffers;
static char preceding_buffer[4096];

int main(int argc, char **argv) {
  assert(argc == 2);
  assert(stdout == &__sF[1] && stderr == &__sF[2]);
  assert(actql_bootstrap_initial_stream_pristine(stdout, 1));
  assert(actql_bootstrap_initial_stream_pristine(stderr, 2));
  if (strcmp(argv[1], "buffered-output") == 0 ||
      strcmp(argv[1], "buffered-error") == 0) {
    FILE *changed = strcmp(argv[1], "buffered-output") == 0 ? stdout : stderr;
    assert(setvbuf(changed, preceding_buffer, _IOFBF, sizeof(preceding_buffer)) == 0);
    assert(!actql_bootstrap_bind_initial_command_output(&streams, &buffers,
      stdout, stderr));
    assert(streams.attempted && !streams.captured && !buffers.attempted);
    assert(setup_calls == 0);
    assert(changed->_bf._base == (unsigned char *)preceding_buffer);
    assert(!actql_bootstrap_bind_initial_command_output(&streams, &buffers,
      stdout, stderr));
    assert(setup_calls == 0);
  } else if (strcmp(argv[1], "used-error") == 0) {
    assert(fputc('X', stderr) == 'X' && fflush(stderr) == 0);
    assert(!actql_bootstrap_bind_initial_command_output(&streams, &buffers,
      stdout, stderr));
    assert(!buffers.attempted && setup_calls == 0);
  } else if (strcmp(argv[1], "foreign-output") == 0) {
    FILE copy = *stdout;
    assert(!actql_bootstrap_bind_initial_command_output(&streams, &buffers,
      &copy, stderr));
    assert(!buffers.attempted && setup_calls == 0);
  } else {
    assert(strcmp(argv[1], "original") == 0 ||
      strcmp(argv[1], "changed-metadata") == 0);
    assert(actql_bootstrap_bind_initial_command_output(&streams, &buffers,
      stdout, stderr));
    assert(setup_calls == 2 && streams.captured);
    assert(actql_bootstrap_command_stdio_current(&streams, stdout, stderr));
    assert(actql_bootstrap_command_output_current(&buffers, stdout, stderr));
    assert(!actql_bootstrap_bind_initial_command_output(&streams, &buffers,
      stdout, stderr));
    assert(setup_calls == 2);
    if (strcmp(argv[1], "changed-metadata") == 0) {
      struct __sFILEX *extra = stdout->_extra;
      stdout->_extra = NULL;
      assert(!actql_bootstrap_command_stdio_current(&streams, stdout, stderr));
      stdout->_extra = extra;
      assert(actql_bootstrap_command_stdio_current(&streams, stdout, stderr));
      int (*write)(void *, const char *, int) = stdout->_write;
      stdout->_write = NULL;
      assert(!actql_bootstrap_command_stdio_current(&streams, stdout, stderr));
      stdout->_write = write;
      assert(actql_bootstrap_command_stdio_current(&streams, stdout, stderr));
    } else {
      /* Use both real standard FILEs across their original buffer boundary. */
      for (size_t index = 0; index < 5000; ++index) {
        assert(fputc('O', stdout) == 'O');
        assert(fputc('E', stderr) == 'E');
      }
      assert(fflush(stdout) == 0 && fflush(stderr) == 0);
      assert(actql_bootstrap_command_stdio_current(&streams, stdout, stderr));
      assert(actql_bootstrap_command_output_current(&buffers, stdout, stderr));
    }
  }
  /* These are process-lived standard FILEs, not fixture-owned tmpfiles. The
   * original static buffers stay alive; successful flush is not FILE retirement.
   * Reporting happens only after the preinitialization case has completed. */
  assert(fputs("original initial stdio passed\n", stdout) >= 0);
  assert(fflush(stdout) == 0 && fflush(stderr) == 0);
  return 0;
}
