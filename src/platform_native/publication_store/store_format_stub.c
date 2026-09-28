#define _POSIX_C_SOURCE 200809L

#include "moonbit.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef O_NOFOLLOW
#define O_NOFOLLOW 0
#endif

static const char marker_name[] = "publication-format.json";
static const char lock_name[] = ".actql-publication.lock";
static const char format_body[] =
  "{\"version\":\"actql-native-publication-store/0.1\","
  "\"isolation\":\"execution-namespace\"}";

// 0 = admitted, 1 = legacy data, 2 = unidentified format, 3 = I/O failure.
// The first call inspects without writing. The second is made under the
// publication lock and creates the marker only for an otherwise empty root.
int32_t actql_native_publication_store_format(
  moonbit_bytes_t path,
  int32_t length,
  int32_t establish
) {
  if (length <= 0 || memchr(path, '\0', (size_t)length) != NULL) return 3;
  char *name = malloc((size_t)length + 1);
  if (name == NULL) return 3;
  memcpy(name, path, (size_t)length);
  name[length] = '\0';
  int root = open(name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  free(name);
  if (root < 0) return 3;
  int duplicate = dup(root);
  if (duplicate < 0) {
    close(root);
    return 3;
  }
  DIR *entries = fdopendir(duplicate);
  if (entries == NULL) {
    close(duplicate);
    close(root);
    return 3;
  }
  int found_marker = 0;
  int other = 0;
  int legacy = 0;
  struct dirent *entry;
  errno = 0;
  while ((entry = readdir(entries)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 ||
        strcmp(entry->d_name, "..") == 0 ||
        strcmp(entry->d_name, lock_name) == 0) continue;
    if (strcmp(entry->d_name, marker_name) == 0) {
      found_marker = 1;
    } else {
      other = 1;
      if (strcmp(entry->d_name, ".actql-publication.sqlite3") == 0 ||
          strncmp(entry->d_name, "publication-", 12) == 0) legacy = 1;
    }
    errno = 0;
  }
  int read_error = errno;
  closedir(entries);
  if (read_error != 0) {
    close(root);
    return 3;
  }
  if (found_marker) {
    int marker = openat(root, marker_name,
      O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (marker < 0) {
      close(root);
      return 2;
    }
    struct stat status;
    char body[sizeof(format_body)];
    ssize_t count = read(marker, body, sizeof(body));
    int valid = fstat(marker, &status) == 0 && S_ISREG(status.st_mode) &&
      status.st_size == (off_t)(sizeof(format_body) - 1) &&
      count == (ssize_t)(sizeof(format_body) - 1) &&
      memcmp(body, format_body, sizeof(format_body) - 1) == 0;
    close(marker);
    close(root);
    return valid ? 0 : 2;
  }
  if (other) {
    close(root);
    return legacy ? 1 : 2;
  }
  if (!establish) {
    close(root);
    return 0;
  }
  int marker = openat(root, marker_name,
    O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (marker < 0) {
    close(root);
    return 3;
  }
  size_t remaining = sizeof(format_body) - 1;
  const char *cursor = format_body;
  while (remaining > 0) {
    ssize_t count = write(marker, cursor, remaining);
    if (count <= 0) {
      close(marker);
      close(root);
      return 3;
    }
    cursor += count;
    remaining -= (size_t)count;
  }
  int durable = fsync(marker) == 0 && fsync(root) == 0;
  close(marker);
  close(root);
  return durable ? 0 : 3;
}
