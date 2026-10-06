#define _DARWIN_C_SOURCE
#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L
#include "moonbit.h"
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// This owner only copies pinned read-only files. SQLite never opens the
// unclassified source. The copy includes WAL; SHM is rebuilt on the copy.
typedef struct {
  char *source;
  char *wal;
  char *journal;
  char *directory;
  char *copy;
  int descriptors[2];
  int output_descriptor;
  struct stat identities[2];
  int count;
  int ready;
  int absent;
  char error[256];
} actql_journal_inspection;

static void inspection_error(actql_journal_inspection *owner, const char *text) {
  snprintf(owner->error, sizeof(owner->error), "%s", text);
}

static char *inspection_suffix(const char *path, const char *suffix) {
  size_t length = strlen(path) + strlen(suffix) + 1;
  char *result = malloc(length);
  if (result != NULL) snprintf(result, length, "%s%s", path, suffix);
  return result;
}

static int inspection_same(const struct stat *a, const struct stat *b) {
  if (a->st_dev != b->st_dev || a->st_ino != b->st_ino ||
      a->st_size != b->st_size) return 0;
#ifdef __APPLE__
  return a->st_mtimespec.tv_sec == b->st_mtimespec.tv_sec &&
    a->st_mtimespec.tv_nsec == b->st_mtimespec.tv_nsec &&
    a->st_ctimespec.tv_sec == b->st_ctimespec.tv_sec &&
    a->st_ctimespec.tv_nsec == b->st_ctimespec.tv_nsec;
#else
  return a->st_mtim.tv_sec == b->st_mtim.tv_sec &&
    a->st_mtim.tv_nsec == b->st_mtim.tv_nsec &&
    a->st_ctim.tv_sec == b->st_ctim.tv_sec &&
    a->st_ctim.tv_nsec == b->st_ctim.tv_nsec;
#endif
}

static int inspection_remove(const char *path) {
  return unlink(path) == 0 || errno == ENOENT;
}

static int inspection_close(actql_journal_inspection *owner) {
  if (owner->output_descriptor >= 0) {
    if (close(owner->output_descriptor) != 0) {
      inspection_error(owner, "close inspection copy failed");
      return 0;
    }
    owner->output_descriptor = -1;
  }
  for (int index = 0; index < 2; index++) {
    if (owner->descriptors[index] >= 0) {
      if (close(owner->descriptors[index]) != 0) {
        inspection_error(owner, "close inspection source failed");
        return 0;
      }
      owner->descriptors[index] = -1;
    }
  }
  if (owner->copy != NULL) {
    const char *suffixes[] = {"", "-wal", "-shm", "-journal"};
    for (int index = 0; index < 4; index++) {
      char *path = inspection_suffix(owner->copy, suffixes[index]);
      if (path == NULL) {
        inspection_error(owner, "inspection cleanup allocation failed");
        return 0;
      }
      int removed = inspection_remove(path);
      free(path);
      if (!removed) {
        inspection_error(owner, "remove inspection copy failed");
        return 0;
      }
    }
  }
  if (owner->directory != NULL) {
    if (rmdir(owner->directory) != 0 && errno != ENOENT) {
      inspection_error(owner, "remove inspection directory failed");
      return 0;
    }
    free(owner->directory);
    owner->directory = NULL;
  }
  // A later finalizer must not touch a completed owner's old pathname if
  // another directory has since been created there.
  free(owner->copy);
  owner->copy = NULL;
  owner->ready = 0;
  return 1;
}

static void inspection_finalize(void *value) {
  actql_journal_inspection *owner = value;
  (void)inspection_close(owner);
  free(owner->source);
  free(owner->wal);
  free(owner->journal);
  free(owner->directory);
  free(owner->copy);
}

void *actql_journal_inspection_open(moonbit_bytes_t path, int32_t length) {
  actql_journal_inspection *owner = moonbit_make_external_object(
    inspection_finalize, sizeof(actql_journal_inspection));
  memset(owner, 0, sizeof(*owner));
  owner->descriptors[0] = owner->descriptors[1] = -1;
  owner->output_descriptor = -1;
  if (length <= 0 || memchr(path, 0, (size_t)length) != NULL) {
    inspection_error(owner, "invalid inspection path");
    return owner;
  }
  owner->source = malloc((size_t)length + 1);
  if (owner->source == NULL) {
    inspection_error(owner, "inspection path allocation failed");
    return owner;
  }
  memcpy(owner->source, path, (size_t)length);
  owner->source[length] = 0;
  owner->wal = inspection_suffix(owner->source, "-wal");
  owner->journal = inspection_suffix(owner->source, "-journal");
  if (owner->wal == NULL || owner->journal == NULL) {
    inspection_error(owner, "inspection path allocation failed");
    return owner;
  }
  struct stat info;
  if (lstat(owner->journal, &info) == 0 || errno != ENOENT) {
    inspection_error(owner, "rollback journal requires reconciliation");
    return owner;
  }
  if (lstat(owner->source, &info) != 0) {
    if (errno == ENOENT && lstat(owner->wal, &info) != 0 && errno == ENOENT) {
      owner->absent = owner->ready = 1;
    } else inspection_error(owner, "inspect source database failed");
    return owner;
  }
  const char *paths[] = {owner->source, owner->wal};
  for (int index = 0; index < 2; index++) {
    int descriptor = open(paths[index], O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (descriptor < 0) {
      if (index == 1 && errno == ENOENT) break;
      inspection_error(owner, "open inspection source failed");
      return owner;
    }
    owner->descriptors[index] = descriptor;
    owner->count++;
    if (fstat(descriptor, &owner->identities[index]) != 0 ||
        !S_ISREG(owner->identities[index].st_mode) ||
        owner->identities[index].st_size < 0) {
      inspection_error(owner, "invalid inspection source");
      return owner;
    }
  }
  const char *temporary = getenv("TMPDIR");
  if (temporary == NULL || temporary[0] == 0) temporary = "/tmp";
  char *parent = strdup(owner->source);
  char *slash = parent == NULL ? NULL : strrchr(parent, '/');
  if (parent != NULL) {
    if (slash == NULL) strcpy(parent, ".");
    else if (slash == parent) parent[1] = 0;
    else *slash = 0;
  }
  char *source_directory = parent == NULL ? NULL : realpath(parent, NULL);
  char *scratch_directory = realpath(temporary, NULL);
  free(parent);
  int safe_scratch = source_directory != NULL && scratch_directory != NULL;
  if (safe_scratch) {
    size_t source_length = strlen(source_directory);
    safe_scratch = strncmp(source_directory, scratch_directory, source_length) != 0 ||
      (scratch_directory[source_length] != 0 && scratch_directory[source_length] != '/');
    if (source_length == 1 && source_directory[0] == '/') safe_scratch = 0;
  }
  free(source_directory);
  free(scratch_directory);
  if (!safe_scratch) {
    inspection_error(owner, "inspection scratch overlaps source directory");
    return owner;
  }
  owner->directory = inspection_suffix(temporary, "/actql-journal-format-XXXXXX");
  if (owner->directory == NULL || mkdtemp(owner->directory) == NULL) {
    // No ownership of a directory was acquired if mkdtemp failed.
    free(owner->directory);
    owner->directory = NULL;
    inspection_error(owner, "create inspection directory failed");
    return owner;
  }
  owner->copy = inspection_suffix(owner->directory, "/journal.sqlite3");
  if (owner->copy == NULL) {
    inspection_error(owner, "inspection copy path allocation failed");
    return owner;
  }
  for (int index = 0; index < owner->count; index++) {
    char *target = inspection_suffix(owner->copy, index == 0 ? "" : "-wal");
    if (target == NULL) {
      inspection_error(owner, "inspection copy path allocation failed");
      return owner;
    }
    int output = open(target, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    free(target);
    if (output < 0) {
      inspection_error(owner, "create inspection copy failed");
      return owner;
    }
    owner->output_descriptor = output;
    unsigned char bytes[65536];
    off_t position = 0;
    int complete = 1;
    while (position < owner->identities[index].st_size) {
      off_t remaining = owner->identities[index].st_size - position;
      size_t count = remaining < (off_t)sizeof(bytes) ? (size_t)remaining : sizeof(bytes);
      ssize_t read_count = pread(owner->descriptors[index], bytes, count, position);
      if (read_count < 0 && errno == EINTR) continue;
      if (read_count <= 0) { complete = 0; break; }
      ssize_t written = 0;
      while (written < read_count) {
        ssize_t result = write(output, bytes + written, (size_t)(read_count - written));
        if (result < 0 && errno == EINTR) continue;
        if (result <= 0) { complete = 0; break; }
        written += result;
      }
      if (!complete) break;
      position += read_count;
    }
    if (close(output) != 0) {
      inspection_error(owner, "copy inspection source failed");
      return owner;
    }
    owner->output_descriptor = -1;
    if (!complete) {
      inspection_error(owner, "copy inspection source failed");
      return owner;
    }
  }
  owner->ready = 1;
  return owner;
}

int32_t actql_journal_inspection_ready(actql_journal_inspection *owner) {
  return owner->ready;
}

moonbit_bytes_t actql_journal_inspection_path(actql_journal_inspection *owner) {
  const char *path = owner->copy == NULL ? "" : owner->copy;
  int32_t length = (int32_t)strlen(path);
  moonbit_bytes_t result = moonbit_make_bytes_raw(length);
  if (length > 0) memcpy(result, path, (size_t)length);
  return result;
}

moonbit_bytes_t actql_journal_inspection_error(actql_journal_inspection *owner) {
  int32_t length = (int32_t)strlen(owner->error);
  moonbit_bytes_t result = moonbit_make_bytes_raw(length);
  if (length > 0) memcpy(result, owner->error, (size_t)length);
  return result;
}

int32_t actql_journal_inspection_validate(actql_journal_inspection *owner) {
  struct stat info;
  if (!owner->ready) return 0;
  if (lstat(owner->journal, &info) == 0 || errno != ENOENT) goto changed;
  if (owner->absent) {
    if (lstat(owner->source, &info) == 0 || errno != ENOENT) goto changed;
  } else {
    const char *paths[] = {owner->source, owner->wal};
    for (int index = 0; index < owner->count; index++) {
      if (fstat(owner->descriptors[index], &info) != 0 ||
          !inspection_same(&info, &owner->identities[index]) ||
          lstat(paths[index], &info) != 0 ||
          !inspection_same(&info, &owner->identities[index])) goto changed;
    }
  }
  if (owner->count < 2 &&
      (lstat(owner->wal, &info) == 0 || errno != ENOENT)) goto changed;
  return 1;
changed:
  inspection_error(owner, "inspection source changed");
  return 0;
}

int32_t actql_journal_inspection_close(actql_journal_inspection *owner) {
  return inspection_close(owner);
}
