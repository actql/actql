#define _POSIX_C_SOURCE 200809L

#include "moonbit.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum { ACTQL_PROCESS_IMAGE_MAX_CHUNK = 1048576 };

typedef struct {
  int descriptor;
  unsigned char *buffer;
  size_t capacity;
  int32_t length;
  bool eof;
  char *error;
} actql_native_process_image_reader;

static void actql_process_image_replace_error(
  actql_native_process_image_reader *reader,
  const char *message
) {
  free(reader->error);
  reader->error = NULL;
  if (message == NULL) return;
  size_t length = strlen(message);
  reader->error = malloc(length + 1);
  if (reader->error != NULL) memcpy(reader->error, message, length + 1);
}

static void actql_process_image_reader_finalize(void *value) {
  actql_native_process_image_reader *reader = value;
  if (reader->descriptor >= 0) {
    close(reader->descriptor);
    reader->descriptor = -1;
  }
  free(reader->buffer);
  reader->buffer = NULL;
  free(reader->error);
  reader->error = NULL;
}

static bool actql_process_image_path(char output[PATH_MAX]) {
#if defined(__APPLE__)
  uint32_t size = PATH_MAX;
  return _NSGetExecutablePath(output, &size) == 0;
#elif defined(__linux__)
  ssize_t length = readlink("/proc/self/exe", output, PATH_MAX - 1);
  if (length < 1 || length >= PATH_MAX) return false;
  output[length] = '\0';
  return true;
#else
  (void)output;
  return false;
#endif
}

MOONBIT_FFI_EXPORT
void *actql_native_process_image_open_reader(int64_t max_bytes) {
  actql_native_process_image_reader *reader = moonbit_make_external_object(
    actql_process_image_reader_finalize,
    sizeof(actql_native_process_image_reader)
  );
  memset(reader, 0, sizeof(*reader));
  reader->descriptor = -1;
  if (max_bytes < 1) {
    actql_process_image_replace_error(reader, "invalid process image limit");
    return reader;
  }
  char path[PATH_MAX];
  if (!actql_process_image_path(path)) {
    actql_process_image_replace_error(reader, "process image path unavailable");
    return reader;
  }
  reader->descriptor = open(path, O_RDONLY | O_CLOEXEC);
  if (reader->descriptor < 0) {
    actql_process_image_replace_error(reader, strerror(errno));
    return reader;
  }
  struct stat status;
  if (fstat(reader->descriptor, &status) != 0) {
    actql_process_image_replace_error(reader, strerror(errno));
    close(reader->descriptor);
    reader->descriptor = -1;
    return reader;
  }
  if (!S_ISREG(status.st_mode)) {
    actql_process_image_replace_error(reader, "process image is not a regular file");
    close(reader->descriptor);
    reader->descriptor = -1;
    return reader;
  }
  if (status.st_size < 1 || status.st_size > max_bytes) {
    actql_process_image_replace_error(reader, "capacity exceeded");
    close(reader->descriptor);
    reader->descriptor = -1;
    return reader;
  }
  return reader;
}

MOONBIT_FFI_EXPORT
bool actql_native_process_image_reader_ready(
  actql_native_process_image_reader *reader
) {
  return reader != NULL && reader->descriptor >= 0;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t actql_native_process_image_reader_error(
  actql_native_process_image_reader *reader
) {
  const char *message = reader == NULL || reader->error == NULL
    ? "process image reader failed" : reader->error;
  size_t length = strlen(message);
  moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)length);
  if (length > 0) memcpy(result, message, length);
  return result;
}

MOONBIT_FFI_EXPORT
int32_t actql_native_process_image_reader_next(
  actql_native_process_image_reader *reader,
  int32_t max_bytes
) {
  if (reader == NULL || reader->descriptor < 0 || reader->eof ||
      max_bytes < 1 || max_bytes > ACTQL_PROCESS_IMAGE_MAX_CHUNK) {
    return 1;
  }
  size_t requested = (size_t)max_bytes;
  if (reader->capacity < requested) {
    unsigned char *replacement = realloc(reader->buffer, requested);
    if (replacement == NULL) {
      actql_process_image_replace_error(reader, "process image allocation failed");
      return 2;
    }
    reader->buffer = replacement;
    reader->capacity = requested;
  }
  ssize_t count;
  do {
    count = read(reader->descriptor, reader->buffer, requested);
  } while (count < 0 && errno == EINTR);
  if (count < 0) {
    actql_process_image_replace_error(reader, strerror(errno));
    return 2;
  }
  reader->length = (int32_t)count;
  reader->eof = count == 0;
  return 0;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t actql_native_process_image_reader_chunk(
  actql_native_process_image_reader *reader
) {
  int32_t length = reader == NULL ? 0 : reader->length;
  moonbit_bytes_t result = moonbit_make_bytes_raw(length);
  if (length > 0) memcpy(result, reader->buffer, (size_t)length);
  return result;
}

MOONBIT_FFI_EXPORT
bool actql_native_process_image_reader_eof(
  actql_native_process_image_reader *reader
) {
  return reader == NULL || reader->eof;
}

MOONBIT_FFI_EXPORT
int32_t actql_native_process_image_reader_close(
  actql_native_process_image_reader *reader
) {
  if (reader == NULL || reader->descriptor < 0) return 0;
  int descriptor = reader->descriptor;
  reader->descriptor = -1;
  if (close(descriptor) == 0) return 0;
  actql_process_image_replace_error(reader, strerror(errno));
  return 1;
}
