#define _DARWIN_C_SOURCE
#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L
#include "moonbit.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/attr.h>
#include <sys/mount.h>
#endif

#ifdef ACTQL_SCOPED_READ_ALLOCATOR
#include "scoped_read.h"
#include "../host_bootstrap/command_platform.h"
#define malloc actql_native_file_scoped_allocate
#define free actql_native_file_scoped_free
static char *inspection_scoped_strdup(const char *text) {
  size_t length = strlen(text);
  if (length == SIZE_MAX) return NULL;
  char *copy = malloc(length + 1);
  if (copy != NULL) memcpy(copy, text, length + 1);
  return copy;
}
#define strdup inspection_scoped_strdup
#endif

static char *inspection_canonical_path(const char *path) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  // Keep the canonical result in the same original Read allocation route.
  // realpath(NULL) would allocate an unrelated libc-owned result instead.
  char *resolved = malloc(PATH_MAX);
  if (resolved == NULL) return NULL;
  if (realpath(path, resolved) == NULL) {
    free(resolved);
    return NULL;
  }
  return resolved;
#else
  return realpath(path, NULL);
#endif
}

// This owner only copies pinned read-only files. SQLite never opens the
// unclassified source. The copy includes WAL; SHM is rebuilt on the copy.
typedef struct {
  char *source;
  char *wal;
  char *journal;
  char *directory;
  char *copy;
  int descriptors[2];
  int descriptor_close_errno[2];
  int output_descriptor;
  int output_close_errno;
  int path_descriptor;
  int path_close_errno;
  int private_index_attempted;
  int private_index_created;
  int private_index_identity_observed;
  int private_index_primary_errno;
  int private_index_ready;
  int private_index_close_unknown;
  int private_index_descriptor;
  struct stat private_index_identity;
  struct stat identities[2];
  int count;
  int ready;
  int absent;
  int limit_exceeded;
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

// Each original descriptor gets one close attempt. An unconfirmed result
// retains its number and errno as cleanup duty, never as a retryable FD.
static int inspection_close_descriptor(int *descriptor, int *close_errno) {
  if (*close_errno != 0) return 0;
  if (*descriptor < 0) return 1;
  *close_errno = EIO;
  if (close(*descriptor) != 0) {
    *close_errno = errno != 0 ? errno : EIO;
    return 0;
  }
  *descriptor = -1;
  *close_errno = 0;
  return 1;
}

/* The selected command resolves an existing directory through its original
 * descriptor and a fixed kernel attribute buffer, not libc realpath/getcwd
 * working storage. This descriptor has its own one-shot close responsibility. */
static char *inspection_command_directory_path(
    actql_journal_inspection *owner, const char *path) {
#ifdef __APPLE__
  if (owner->path_close_errno || owner->path_descriptor >= 0) return NULL;
  owner->path_descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (owner->path_descriptor < 0) return NULL;
  struct statfs filesystem;
  char *resolved = NULL;
  if (fstatfs(owner->path_descriptor, &filesystem) == 0 &&
      !(filesystem.f_flags & MNT_UNION) &&
      memcmp(filesystem.f_fstypename, "apfs", sizeof("apfs")) == 0) {
    struct attrlist attributes = {0};
    attributes.bitmapcount = ATTR_BIT_MAP_COUNT;
    attributes.commonattr = ATTR_CMN_FULLPATH;
    unsigned char buffer[sizeof(uint32_t) + sizeof(attrreference_t) + PATH_MAX];
    memset(buffer, 0, sizeof(buffer));
    if (fgetattrlist(owner->path_descriptor, &attributes, buffer,
        sizeof(buffer), FSOPT_REPORT_FULLSIZE) == 0) {
      uint32_t bytes;
      attrreference_t reference;
      memcpy(&bytes, buffer, sizeof(bytes));
      if (bytes >= sizeof(bytes) + sizeof(reference) && bytes <= sizeof(buffer)) {
        memcpy(&reference, buffer + sizeof(bytes), sizeof(reference));
        if (reference.attr_dataoffset >= (int32_t)sizeof(reference) &&
            reference.attr_length > 1 && reference.attr_length <= PATH_MAX) {
          size_t offset = sizeof(bytes) + (size_t)reference.attr_dataoffset;
          if (offset <= bytes && reference.attr_length <= bytes - offset &&
              buffer[offset] == '/' &&
              buffer[offset + reference.attr_length - 1] == 0 &&
              memchr(buffer + offset, 0, reference.attr_length - 1) == NULL) {
            resolved = malloc(PATH_MAX);
            if (resolved != NULL)
              memcpy(resolved, buffer + offset, reference.attr_length);
          }
        }
      }
    }
  }
  if (!inspection_close_descriptor(&owner->path_descriptor,
      &owner->path_close_errno)) {
    free(resolved);
    return NULL;
  }
  return resolved;
#else
  (void)owner;
  (void)path;
  return NULL;
#endif
}

static int inspection_close(actql_journal_inspection *owner) {
  // A consumed close cannot be retried through a possibly reused number.
  if (owner->private_index_close_unknown || owner->output_close_errno != 0 ||
      owner->path_close_errno != 0 ||
      owner->descriptor_close_errno[0] != 0 ||
      owner->descriptor_close_errno[1] != 0) return 0;
  if (owner->path_descriptor >= 0 &&
      !inspection_close_descriptor(&owner->path_descriptor,
        &owner->path_close_errno)) {
    inspection_error(owner, "close inspection path observation failed");
    return 0;
  }
  if (owner->output_descriptor >= 0) {
    if (!inspection_close_descriptor(&owner->output_descriptor,
                                     &owner->output_close_errno)) {
      inspection_error(owner, "close inspection copy failed");
      return 0;
    }
  }
  for (int index = 0; index < 2; index++) {
    if (owner->descriptors[index] >= 0) {
      if (!inspection_close_descriptor(&owner->descriptors[index],
                                       &owner->descriptor_close_errno[index])) {
        inspection_error(owner, "close inspection source failed");
        return 0;
      }
    }
  }
  if (owner->copy != NULL) {
    if (owner->private_index_attempted && !owner->absent) {
      char *path = inspection_suffix(owner->copy, "-shm");
      if (path == NULL) return 0;
      struct stat current;
      int status = lstat(path, &current);
      int same = owner->private_index_created &&
        owner->private_index_identity_observed && status == 0 &&
        current.st_dev == owner->private_index_identity.st_dev &&
        current.st_ino == owner->private_index_identity.st_ino;
      int missing = owner->private_index_identity_observed &&
        status != 0 && errno == ENOENT;
      free(path);
      if (!same && !missing) {
        inspection_error(owner, "private inspection index replaced");
        return 0;
      }
    }
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

// Only the captured private copy may select the read-only heap-index route.
// The original source DB/WAL and the generic inspection constructor are not
// changed. SQLite receives a read-only connection, never this writing FD.
int32_t actql_journal_inspection_prepare_private_index(
    actql_journal_inspection *owner) {
  if (owner->private_index_attempted || !owner->ready) return 0;
  owner->private_index_attempted = 1;
  if (owner->absent) return 1;
  char *path = inspection_suffix(owner->copy, "-shm");
  if (path == NULL) {
    inspection_error(owner, "private inspection index allocation failed");
    return 0;
  }
  int descriptor = open(path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                        0600);
  if (descriptor < 0) {
    free(path);
    inspection_error(owner, "create private inspection index failed");
    return 0;
  }
  owner->private_index_created = 1;
  owner->private_index_descriptor = descriptor;
  // Confirmed open custody precedes the first stat. A stat failure still
  // consumes exactly this original close; it does not require a later identity.
  int first_stat = fstat(descriptor, &owner->private_index_identity);
  int observed = first_stat == 0 &&
    S_ISREG(owner->private_index_identity.st_mode) &&
    owner->private_index_identity.st_size == 0 &&
    owner->private_index_identity.st_nlink == 1;
  owner->private_index_identity_observed = observed;
  if (!observed) {
    owner->private_index_primary_errno = first_stat != 0 ? errno : EINVAL;
    // One bounded cleanup-only observation while this exact opened FD is
    // still owned. Keep the first refusal even if its identity is recovered.
    // No pathname reopen or consumed descriptor retry is allowed.
    struct stat cleanup_identity;
    if (fstat(descriptor, &cleanup_identity) == 0 &&
        S_ISREG(cleanup_identity.st_mode) && cleanup_identity.st_size == 0 &&
        cleanup_identity.st_nlink == 1) {
      owner->private_index_identity = cleanup_identity;
      owner->private_index_identity_observed = 1;
    }
  }
  int close_result = close(descriptor);
  if (close_result != 0) {
    owner->private_index_close_unknown = 1;
    inspection_error(owner, "private inspection index close unknown");
  } else if (!observed) {
    owner->private_index_descriptor = -1;
    inspection_error(owner, "inspect private inspection index failed");
  } else {
    owner->private_index_descriptor = -1;
    struct stat current;
    owner->private_index_ready = lstat(path, &current) == 0 &&
      inspection_same(&current, &owner->private_index_identity);
    if (!owner->private_index_ready)
      inspection_error(owner, "private inspection index changed");
  }
  free(path);
  return owner->private_index_ready;
}

int32_t actql_journal_inspection_private_index_ready(
    actql_journal_inspection *owner) {
  if (!owner->ready || !owner->private_index_attempted ||
      owner->private_index_close_unknown) return 0;
  if (owner->absent) return 1;
  if (!owner->private_index_ready) return 0;
  char *path = inspection_suffix(owner->copy, "-shm");
  if (path == NULL) {
    inspection_error(owner, "private inspection index allocation failed");
    return 0;
  }
  struct stat current;
  int ready = lstat(path, &current) == 0 &&
    inspection_same(&current, &owner->private_index_identity);
  free(path);
  if (!ready) inspection_error(owner, "private inspection index changed");
  return ready;
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

static void *inspection_open_bounded_original(
    moonbit_bytes_t path, int32_t length, int64_t max_snapshot_bytes,
    const char *selected_scratch, int command_selected) {
  actql_journal_inspection *owner = moonbit_make_external_object(
    inspection_finalize, sizeof(actql_journal_inspection));
  memset(owner, 0, sizeof(*owner));
  owner->descriptors[0] = owner->descriptors[1] = -1;
  owner->output_descriptor = -1;
  owner->path_descriptor = -1;
  owner->private_index_descriptor = -1;
  if (max_snapshot_bytes < 0 || length <= 0 ||
      memchr(path, 0, (size_t)length) != NULL) {
    inspection_error(owner, "invalid inspection path");
    return owner;
  }
  /* This command's physical Root/member path selection is bounded to 4096
   * encoded bytes. Enforce that same precondition before retained source/WAL/
   * rollback path allocations; never truncate or rename the original path.
   * The generic Coordinator inspection retains its existing input domain. */
  if (command_selected && length > 4096) {
    inspection_error(owner, "original command inspection path unavailable");
    return owner;
  }
  /* The command entry captured this original before the first covered
   * acquisition. Never re-read the environment after admission. Refusal here
   * precedes even opening the source; this same receiver still owns cleanup.
   * The generic Coordinator route retains its existing selection below. */
  if (command_selected &&
      (selected_scratch == NULL || selected_scratch[0] == 0 ||
       strnlen(selected_scratch, 4097) > 4096)) {
    inspection_error(owner, "original command inspection scratch unavailable");
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
  int64_t snapshot_bytes = 0;
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
    if (owner->identities[index].st_size > max_snapshot_bytes - snapshot_bytes) {
      owner->limit_exceeded = 1;
      inspection_error(owner, "inspection snapshot capacity exceeded");
      return owner;
    }
    snapshot_bytes += owner->identities[index].st_size;
  }
  const char *temporary = selected_scratch;
  if (!command_selected) {
    temporary = getenv("TMPDIR");
    if (temporary == NULL || temporary[0] == 0) temporary = "/tmp";
  }
  char *parent = strdup(owner->source);
  char *slash = parent == NULL ? NULL : strrchr(parent, '/');
  if (parent != NULL) {
    if (slash == NULL) strcpy(parent, ".");
    else if (slash == parent) parent[1] = 0;
    else *slash = 0;
  }
  char *source_directory = parent == NULL ? NULL : command_selected
    ? inspection_command_directory_path(owner, parent)
    : inspection_canonical_path(parent);
  char *scratch_directory = command_selected
    ? inspection_command_directory_path(owner, temporary)
    : inspection_canonical_path(temporary);
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
    if (!inspection_close_descriptor(&owner->output_descriptor,
                                     &owner->output_close_errno)) {
      inspection_error(owner, "copy inspection source failed");
      return owner;
    }
    if (!complete) {
      inspection_error(owner, "copy inspection source failed");
      return owner;
    }
  }
  owner->ready = 1;
  return owner;
}

static void *inspection_open_bounded(
    moonbit_bytes_t path, int32_t length, int64_t max_snapshot_bytes) {
  return inspection_open_bounded_original(
    path, length, max_snapshot_bytes, NULL, 0);
}

/* Only the selected command route requires the actual entry original. The
 * borrowed scratch is input correspondence, never Read capacity or permission.
 * Missing coverage does not fall back to TMPDIR or another directory. */
void *actql_journal_inspection_open_command_bounded(
    moonbit_bytes_t path, int32_t length, int64_t max_snapshot_bytes) {
  const char *scratch = NULL;
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  scratch = actql_native_command_platform_scratch_directory(
    actql_native_command_platform_current());
#endif
  return inspection_open_bounded_original(
    path, length, max_snapshot_bytes, scratch, 1);
}

// Keep existing Coordinator admission behavior; new Local callers explicitly
// bound the combined DB/WAL copy before any scratch file is created.
void *actql_journal_inspection_open(moonbit_bytes_t path, int32_t length) {
  return inspection_open_bounded(path, length, INT64_MAX);
}

void *actql_journal_inspection_open_bounded(
    moonbit_bytes_t path, int32_t length, int64_t max_snapshot_bytes) {
  return inspection_open_bounded(path, length, max_snapshot_bytes);
}

int32_t actql_journal_inspection_limit_exceeded(actql_journal_inspection *owner) {
  return owner->limit_exceeded;
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
