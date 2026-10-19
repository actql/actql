#ifndef ACTQL_NATIVE_COMMAND_OUTPUT_H
#define ACTQL_NATIVE_COMMAND_OUTPUT_H

#include <stdbool.h>
#include <stdio.h>
#include <errno.h>

/* Subordinate storage in the existing initial command entry, not another
 * resource Owner or output permission. Both buffers remain with that same
 * process-lived entry, including after a partial setup or default-heap ACK.
 * Libc FILE/lock/TLS bookkeeping remains a separate initial-control term. */
typedef struct {
  FILE *output;
  FILE *error;
  char output_buffer[4096];
  char error_buffer[4096];
  int output_result;
  int error_result;
  int output_errno;
  int error_errno;
  bool attempted;
  bool output_configured;
  bool error_attempted;
  bool error_configured;
} actql_bootstrap_command_output;

/* Observe the supported Native libc's actual backing fields from its selected
 * SDK definition. A successful status alone cannot establish this binding.
 * No generic or foreign FILE layout is inferred on an unsupported backend. */
static bool actql_bootstrap_output_buffer_current(
    FILE *stream, const char *buffer, size_t length) {
#if defined(__APPLE__)
  return stream && stream->_bf._base == (const unsigned char *)buffer &&
    stream->_bf._size >= 0 && (size_t)stream->_bf._size == length;
#else
  (void)stream; (void)buffer; (void)length;
  return false;
#endif
}

/* Called only by the same trusted entry after its complete initial selection
 * and actual managed original. A failed second setup does not forget the
 * first FILE/buffer, retry it, select an alternate buffer or claim cleanup. */
static bool actql_bootstrap_bind_command_output(
    actql_bootstrap_command_output *original, FILE *output, FILE *error) {
#if !defined(__APPLE__)
  (void)original; (void)output; (void)error;
  return false;
#else
  if (!original || original->attempted || !output || !error || output == error)
    return false;
  original->attempted = true;
  original->output = output;
  original->error = error;
  errno = 0;
  original->output_result = setvbuf(output, original->output_buffer,
    _IOFBF, sizeof(original->output_buffer));
  original->output_errno = errno;
  if (original->output_result != 0) return false;
  original->output_configured = true;
  if (!actql_bootstrap_output_buffer_current(output,
      original->output_buffer, sizeof(original->output_buffer))) return false;
  original->error_attempted = true;
  errno = 0;
  original->error_result = setvbuf(error, original->error_buffer,
    _IOFBF, sizeof(original->error_buffer));
  original->error_errno = errno;
  if (original->error_result != 0) return false;
  original->error_configured = true;
  return actql_bootstrap_output_buffer_current(error,
    original->error_buffer, sizeof(original->error_buffer));
#endif
}

static bool actql_bootstrap_command_output_current(
    const actql_bootstrap_command_output *original,
    FILE *output, FILE *error) {
  return original && original->attempted && original->output_configured &&
    original->error_attempted && original->error_configured &&
    original->output_result == 0 && original->error_result == 0 &&
    original->output == output && original->error == error &&
    actql_bootstrap_output_buffer_current(output,
      original->output_buffer, sizeof(original->output_buffer)) &&
    actql_bootstrap_output_buffer_current(error,
      original->error_buffer, sizeof(original->error_buffer));
}

#endif
