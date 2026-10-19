#ifndef ACTQL_NATIVE_COMMAND_INITIAL_STDIO_H
#define ACTQL_NATIVE_COMMAND_INITIAL_STDIO_H

#include <stdbool.h>
#include <stdio.h>
#include "command_output.h"

#if defined(__APPLE__)
/* The selected Darwin libc exports its original standard FILE array. The
 * mutable stdout/stderr pointers alone cannot identify those originals. */
extern FILE __sF[];
#endif

typedef struct {
  FILE *stream;
  struct __sFILEX *extra;
  void *cookie;
  int (*close)(void *);
  int (*read)(void *, char *, int);
  fpos_t (*seek)(void *, fpos_t, int);
  int (*write)(void *, const char *, int);
} actql_bootstrap_command_stream;

/* These are existing libc process-lived originals, not new FILE allocations,
 * a generic stream factory or a capacity issuer. Their libc image, locks and
 * TLS still require the separate complete initial-control coverage. */
typedef struct {
  actql_bootstrap_command_stream output, error;
  bool attempted, captured;
} actql_bootstrap_command_stdio;

static bool actql_bootstrap_initial_stream_pristine(FILE *stream, int number) {
#if defined(__APPLE__)
  if (number != 1 && number != 2) return false;
  return stream == &__sF[number] && stream->_file == number &&
    stream->_flags == (number == 1 ? __SWR : (__SWR | __SNBF)) &&
    !stream->_p && stream->_r == 0 && stream->_w == 0 &&
    !stream->_bf._base && stream->_bf._size == 0 && stream->_lbfsize == 0 &&
    !stream->_ub._base && stream->_ub._size == 0 && stream->_ur == 0 &&
    !stream->_lb._base && stream->_lb._size == 0 &&
    stream->_extra && stream->_cookie == stream && stream->_write;
#else
  (void)stream; (void)number;
  return false;
#endif
}

static void actql_bootstrap_retain_initial_stream(
    actql_bootstrap_command_stream *original, FILE *stream) {
#if defined(__APPLE__)
  original->stream = stream;
  original->extra = stream->_extra;
  original->cookie = stream->_cookie;
  original->close = stream->_close;
  original->read = stream->_read;
  original->seek = stream->_seek;
  original->write = stream->_write;
#else
  (void)original; (void)stream;
#endif
}

/* Check BOTH originals before the first setvbuf. A prior buffer/use or a
 * replacement FILE must not trigger cleanup/rebinding of unaccounted storage
 * inside that call. This one-shot observation performs no FILE operation. */
static bool actql_bootstrap_capture_command_stdio(
    actql_bootstrap_command_stdio *original, FILE *output, FILE *error) {
  if (!original || original->attempted) return false;
  original->attempted = true;
  if (!actql_bootstrap_initial_stream_pristine(output, 1) ||
      !actql_bootstrap_initial_stream_pristine(error, 2)) return false;
  actql_bootstrap_retain_initial_stream(&original->output, output);
  actql_bootstrap_retain_initial_stream(&original->error, error);
  original->captured = true;
  return true;
}

static bool actql_bootstrap_initial_stream_current(
    const actql_bootstrap_command_stream *original, FILE *stream, int number) {
#if defined(__APPLE__)
  return original && (number == 1 || number == 2) &&
    original->stream == stream && stream == &__sF[number] &&
    stream->_file == number && original->extra == stream->_extra &&
    original->cookie == stream->_cookie &&
    original->close == stream->_close && original->read == stream->_read &&
    original->seek == stream->_seek && original->write == stream->_write;
#else
  (void)original; (void)stream; (void)number;
  return false;
#endif
}

static bool actql_bootstrap_command_stdio_current(
    const actql_bootstrap_command_stdio *original, FILE *output, FILE *error) {
  return original && original->attempted && original->captured &&
    actql_bootstrap_initial_stream_current(&original->output, output, 1) &&
    actql_bootstrap_initial_stream_current(&original->error, error, 2);
}

static bool actql_bootstrap_bind_initial_command_output(
    actql_bootstrap_command_stdio *streams,
    actql_bootstrap_command_output *buffers, FILE *output, FILE *error) {
  return actql_bootstrap_capture_command_stdio(streams, output, error) &&
    actql_bootstrap_bind_command_output(buffers, output, error);
}

#endif
