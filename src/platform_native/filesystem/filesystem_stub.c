#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "moonbit.h"
#include "private_file_projection.h"
#include "native_timings.inc"

#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifdef __APPLE__
#include <sys/acl.h>
#include <sys/attr.h>
#include <sys/mount.h>
#elif defined(__linux__)
#include <sys/xattr.h>
#endif

#ifdef ACTQL_SCOPED_READ_ALLOCATOR
#include "scoped_read.h"
#include "../host_bootstrap/command_platform.h"
// The original Core backed-read use and current backing scope must already
// be validated by the installed Native Domain before this physical entrance.
// Outside a selected read scope these hooks use the original allocator.
#define malloc actql_native_file_scoped_allocate
#define calloc actql_native_file_scoped_callocate
#define free actql_native_file_scoped_free
static char *actql_filesystem_scoped_strdup(const char *text) {
  size_t length = strlen(text);
  if (length == SIZE_MAX) return NULL;
  char *copy = malloc(length + 1);
  if (copy != NULL) memcpy(copy, text, length + 1);
  return copy;
}
#define strdup actql_filesystem_scoped_strdup
#define ACTQL_FILESYSTEM_READ_CONTEXT_FIELDS \
  actql_read_context *read_context; bool read_context_user;
#else
#define ACTQL_FILESYSTEM_READ_CONTEXT_FIELDS
#endif

typedef struct {
  ACTQL_FILESYSTEM_READ_CONTEXT_FIELDS
  int fd;
  int32_t diagnostic_ceiling;
  char *error;
  char *custody_path;
  uint64_t result_device;
  uint64_t result_inode;
  int64_t result_size;
  int32_t test_sync_failures;
  int32_t result_directory_acquired;
  int32_t test_directory_inspect_failures;
  int32_t close_result;
  char *close_error;
  DIR *census_stream;
  // Selected command census uses its own descriptor, never a libc DIR. A
  // consumed/unconfirmed close retains this number only as original duty.
  int census_descriptor;
  bool census_descriptor_acquired;
  bool census_descriptor_close_consumed;
  bool census_cleanup_unconfirmed;
  char *census_cleanup_error;
  int32_t test_census_close_failures;
  bool namespace_cleanup_unconfirmed;
  char *namespace_cleanup_error;
  int32_t test_namespace_close_failures;
} actql_native_filesystem_root;

typedef struct {
  actql_native_filesystem_root *root;
  int fd;
  char *error;
  bool ready;
  // 0: not attempted, 1: retired, -1: consumed/unconfirmed; never reclose.
  int32_t close_result;
  char *close_error;
} actql_native_filesystem_lock;

typedef struct {
  actql_native_filesystem_root *root;
  int fd;
  char *staging_name;
  char *final_name;
  char *error;
  int64_t max_bytes;
  int64_t written;
  uint64_t device;
  uint64_t inode;
  bool ready;
  bool staging_present;
  bool final_present;
  bool sealed;
  bool cleanup_requested;
  bool cancelled;
  bool create_conflict;
  bool preserve_names;
  // 0: not attempted, 1: retired, -1: consumed/unconfirmed; never reclose.
  int32_t close_result;
  char *close_error;
} actql_native_filesystem_writer;

typedef struct {
  ACTQL_FILESYSTEM_READ_CONTEXT_FIELDS
  actql_native_filesystem_root *root;
  int fd;
  char *error;
  unsigned char *chunk;
  int32_t diagnostic_ceiling;
  int32_t open_failure_kind;
  int32_t chunk_length;
  int64_t offset;
  uint64_t device;
  uint64_t inode;
  int64_t size;
  bool ready;
  bool eof;
  bool finished;
  // 0: not attempted, 1: acknowledged, -1: sticky diagnostic/unconfirmed.
  // A consumed descriptor number is never a retirement acknowledgement.
  int32_t close_result;
  char *close_error;
} actql_native_filesystem_reader;

enum {
  ACTQL_READER_OPEN_READ_FAILURE = 1,
  ACTQL_READER_OPEN_GENERATION_MISMATCH = 2
};

struct actql_native_private_file_projection {
  actql_native_filesystem_root *root;
  char *name;
  struct stat original;
  uint64_t original_root_device;
  uint64_t original_root_inode;
  bool ready;
};

// Opaque transient facts of a package file on an existing Root. These are not
// private-key installation materials and are never exported/persisted as one.
typedef struct {
  struct stat original;
  uint64_t root_device;
  uint64_t root_inode;
  int32_t issue_kind;
} actql_native_observed_file_stat;

typedef struct {
  uint64_t device;
  uint64_t inode;
  mode_t mode;
  uid_t uid;
  gid_t gid;
  int32_t issue_kind;
} actql_native_observed_directory_stat;

static void actql_replace_error(char **target, const char *message) {
  free(*target);
  *target = NULL;
  if (message == NULL) return;
  size_t length = strlen(message);
  char *copy = malloc(length + 1);
  if (copy == NULL) return;
  memcpy(copy, message, length + 1);
  *target = copy;
}

static void actql_replace_errno_error(
  char **target,
  const char *operation,
  int error_number
) {
  const char *detail = strerror(error_number);
  size_t operation_length = strlen(operation);
  size_t detail_length = strlen(detail);
  if (operation_length > SIZE_MAX - detail_length - 3) {
    actql_replace_error(target, "filesystem error");
    return;
  }
  size_t length = operation_length + detail_length + 2;
  char *message = malloc(length + 1);
  if (message == NULL) {
    actql_replace_error(target, "filesystem error allocation failed");
    return;
  }
  memcpy(message, operation, operation_length);
  message[operation_length] = ':';
  message[operation_length + 1] = ' ';
  memcpy(message + operation_length + 2, detail, detail_length + 1);
  free(*target);
  *target = message;
}

// Positive ceilings are explicit installer input. Zero preserves the legacy
// unbounded diagnostic path and is never evidence of resource funding.
static bool actql_bounded_diagnostic_length(
  const char *text, size_t ceiling, size_t *length
) {
  if (text == NULL) return false;
  for (size_t i = 0; i <= ceiling; i++) {
    if (text[i] == '\0') { *length = i; return true; }
  }
  return false;
}

static bool actql_diagnostic_length(
  const char *text, int32_t ceiling, size_t *length
) {
  if (text == NULL) return false;
  if (ceiling <= 0) { *length = strlen(text); return true; }
  return actql_bounded_diagnostic_length(text, (size_t)ceiling, length);
}

static void actql_replace_bounded_error(
  char **target, int32_t ceiling, const char *text
) {
  free(*target);
  *target = NULL;
  size_t length;
  if (!actql_diagnostic_length(text, ceiling, &length)) return;
  char *copy = malloc(length + 1);
  if (copy == NULL) return;
  memcpy(copy, text, length);
  copy[length] = '\0';
  *target = copy;
}

static void actql_replace_bounded_errno_error(
  char **target, int32_t ceiling, const char *operation, int number
) {
  if (ceiling <= 0) {
    actql_replace_errno_error(target, operation, number);
    return;
  }
  size_t operation_length, detail_length;
  const char *detail = strerror(number);
  if (!actql_diagnostic_length(operation, ceiling, &operation_length) ||
      operation_length > (size_t)ceiling ||
      (size_t)ceiling - operation_length < 2 ||
      !actql_bounded_diagnostic_length(
        detail, (size_t)ceiling - operation_length - 2, &detail_length
      ) || operation_length + detail_length + 2 > (size_t)ceiling) {
    free(*target); *target = NULL;
    return;
  }
  size_t length = operation_length + detail_length + 2;
  char *copy = malloc(length + 1);
  if (copy == NULL) { free(*target); *target = NULL; return; }
  memcpy(copy, operation, operation_length);
  copy[operation_length] = ':'; copy[operation_length + 1] = ' ';
  memcpy(copy + operation_length + 2, detail, detail_length);
  copy[length] = '\0';
  // Preserve the old/new overlap of the original errno replacement path.
  free(*target); *target = copy;
}

static char *actql_copy_text(moonbit_bytes_t bytes, int32_t length) {
  if (length < 0) return NULL;
  char *text = malloc((size_t)length + 1);
  if (text == NULL) return NULL;
  if (length > 0) memcpy(text, bytes, (size_t)length);
  text[length] = '\0';
  return text;
}

static moonbit_bytes_t actql_copy_bytes(const char *text) {
  size_t length = text == NULL ? 0 : strlen(text);
  if (length > INT32_MAX) length = INT32_MAX;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)length);
  if (length > 0) memcpy(bytes, text, length);
  return bytes;
}

static moonbit_bytes_t actql_copy_diagnostic(const char *text, int32_t ceiling) {
  size_t length;
  if (!actql_diagnostic_length(text, ceiling, &length) || length > INT32_MAX)
    length = 0;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)length);
  if (length > 0) memcpy(bytes, text, length);
  return bytes;
}

static bool actql_valid_name(const char *name, size_t length) {
  if (length == 0 || length > 128) return false;
  if ((length == 1 && name[0] == '.') ||
      (length == 2 && name[0] == '.' && name[1] == '.')) {
    return false;
  }
  for (size_t index = 0; index < length; index++) {
    unsigned char character = (unsigned char)name[index];
    if (!((character >= 'a' && character <= 'z') ||
          (character >= 'A' && character <= 'Z') ||
          (character >= '0' && character <= '9') || character == '-' ||
          character == '_' || character == '.')) {
      return false;
    }
  }
  return true;
}

// Ordinary output basenames are not internal object identifiers. Preserve
// their exact bytes and let the selected filesystem enforce its actual limit.
// Every operation remains relative to the original directory descriptor.
static bool actql_valid_file_component(const char *name, size_t length) {
  if (name == NULL || length == 0 ||
      (length == 1 && name[0] == '.') ||
      (length == 2 && name[0] == '.' && name[1] == '.')) return false;
  for (size_t index = 0; index < length; index++) {
    if (name[index] == '\0' || name[index] == '/') return false;
  }
  return true;
}

// Expected names use a private borrowed FFI frame: kind byte, ASCII name, NUL.
// It is not a persisted wire, identity domain or permission. The existing
// formal inventory intake bounds apply before temporary state is allocated.
static bool actql_census_frame_valid(
  const unsigned char *frame, int32_t length, int32_t count
) {
  if (length < 0 || length > 65536 || count < 0 || count > (8192 - 5) / 5)
    return false;
  int32_t offset = 0;
  const char *previous = NULL;
  for (int32_t index = 0; index < count; index++) {
    if (offset >= length || (frame[offset] != 'f' && frame[offset] != 'd'))
      return false;
    const char *name = (const char *)(frame + offset + 1);
    const unsigned char *end = memchr(frame + offset + 1, 0,
      (size_t)(length - offset - 1));
    if (end == NULL) return false;
    size_t name_length = (size_t)(end - (frame + offset + 1));
    bool selected_scope_directory = frame[offset] == 'd' &&
      name_length == 6 && memcmp(name, "@actql", 6) == 0;
    if ((!actql_valid_name(name, name_length) && !selected_scope_directory) ||
        (previous != NULL && strcmp(previous, name) >= 0)) return false;
    previous = name;
    offset = (int32_t)(end - frame) + 1;
  }
  return offset == length;
}

static void actql_census_unconfirmed(
  actql_native_filesystem_root *root, const char *operation, int error_number
) {
  root->census_cleanup_unconfirmed = true;
  actql_replace_bounded_errno_error(&root->census_cleanup_error,
    root->diagnostic_ceiling, operation, error_number);
  actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
    root->census_cleanup_error);
}

// Compare only immediate names and kinds at the same opened directory. Named
// namespace, member bytes/mode/hash and current authority are separate facts.
int32_t actql_native_filesystem_directory_census(
  actql_native_filesystem_root *root, moonbit_bytes_t frame,
  int32_t length, int32_t count
) {
  if (!actql_census_frame_valid(frame, length, count)) return 4;
  if (root == NULL || root->fd < 0 || root->census_stream != NULL ||
      (root->census_descriptor_acquired &&
       !root->census_descriptor_close_consumed)) return -1;
  if (root->census_cleanup_unconfirmed || root->namespace_cleanup_unconfirmed) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      root->census_cleanup_unconfirmed ? root->census_cleanup_error : root->namespace_cleanup_error);
    return 3;
  }
  struct stat original;
  if (fstat(root->fd, &original) != 0 || !S_ISDIR(original.st_mode)) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      "directory census Root is unavailable");
    return -1;
  }
  unsigned char *seen = count == 0 ? NULL : calloc((size_t)count, 1);
  if (count != 0 && seen == NULL) return 2;
  // Opening dot relative to the pinned Root preserves its own directory
  // position. It does not adopt another Root or follow a namespace symlink.
  int descriptor = openat(root->fd, ".",
    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (descriptor < 0) {
    free(seen);
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling,
      "open directory census", errno);
    return -1;
  }
  DIR *stream = fdopendir(descriptor);
  if (stream == NULL) {
    int open_error = errno;
    free(seen);
    if (close(descriptor) != 0) {
      actql_census_unconfirmed(root, "close rejected directory census", errno);
      return 3;
    }
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling,
      "construct directory census", open_error);
    return -1;
  }
  root->census_stream = stream;
  int32_t result = 0, observed = 0;
  while (true) {
    errno = 0;
    struct dirent *entry = readdir(stream);
    if (entry == NULL) {
      if (errno != 0) {
        actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling,
          "read directory census", errno);
        result = -1;
      }
      break;
    }
    // Dot entries consume at most two additional observations. Unknown or
    // repeated names never create a retained list or an unbounded scan.
    if (++observed > count + 2) {result = 1; break;}
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
      continue;
    int32_t offset = 0, matched = -1;
    unsigned char kind = 0;
    for (int32_t index = 0; index < count; index++) {
      const char *name = (const char *)(frame + offset + 1);
      if (strcmp(name, entry->d_name) == 0) {
        matched = index; kind = frame[offset]; break;
      }
      offset += (int32_t)strlen(name) + 2;
    }
    if (matched < 0 || seen[matched] != 0) {result = 1; break;}
    struct stat member;
    if (fstatat(root->fd, entry->d_name, &member, AT_SYMLINK_NOFOLLOW) != 0) {
      int read_error = errno;
      result = read_error == ENOENT ? 1 : -1;
      actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling,
        "inspect directory census member", read_error);
      break;
    }
    if ((kind == 'f' && !S_ISREG(member.st_mode)) ||
        (kind == 'd' && !S_ISDIR(member.st_mode))) {result = 1; break;}
    seen[matched] = 1;
  }
  if (result == 0) {
    for (int32_t index = 0; index < count; index++) {
      if (seen[index] == 0) {result = 1; break;}
    }
    struct stat current;
    if (fstat(root->fd, &current) != 0 ||
        current.st_dev != original.st_dev || current.st_ino != original.st_ino ||
        current.st_mode != original.st_mode || current.st_nlink == 0 ||
        current.st_mtime != original.st_mtime || current.st_ctime != original.st_ctime)
      result = 1;
#ifdef __APPLE__
    else if (current.st_mtimespec.tv_nsec != original.st_mtimespec.tv_nsec ||
             current.st_ctimespec.tv_nsec != original.st_ctimespec.tv_nsec) result = 1;
#elif defined(__linux__)
    else if (current.st_mtim.tv_nsec != original.st_mtim.tv_nsec ||
             current.st_ctim.tv_nsec != original.st_ctim.tv_nsec) result = 1;
#endif
  }
  free(seen);
  root->census_stream = NULL;
  int closed = closedir(stream), close_error = errno;
  if (root->test_census_close_failures > 0) {
    root->test_census_close_failures--;
    closed = -1; close_error = EIO;
  }
  if (closed != 0) {
    // closedir may have consumed its stream; never retry through a potentially
    // reused descriptor or freed DIR pointer. Keep Unknown on this same Root.
    actql_census_unconfirmed(root, "close directory census", close_error);
    return 3;
  }
  return result;
}

#include "command_directory_census.inc"

void actql_native_filesystem_test_fail_census_close(
  actql_native_filesystem_root *root, int32_t failures
) {
  if (root != NULL) root->test_census_close_failures = failures;
}

static bool actql_stat_regular_at(
  actql_native_filesystem_root *root,
  const char *name,
  struct stat *status
) {
  if (root == NULL || root->fd < 0) return false;
  if (fstatat(root->fd, name, status, AT_SYMLINK_NOFOLLOW) != 0) return false;
  return S_ISREG(status->st_mode);
}

static bool actql_exact_generation(
  const struct stat *status,
  uint64_t device,
  uint64_t inode,
  int64_t size
) {
  return (uint64_t)status->st_dev == device &&
         (uint64_t)status->st_ino == inode &&
         status->st_size >= 0 && (int64_t)status->st_size == size;
}

static int actql_sync_root(actql_native_filesystem_root *root) {
  if (root == NULL || root->fd < 0) {
    errno = EBADF;
    return -1;
  }
  if (root->test_sync_failures > 0) {
    root->test_sync_failures -= 1;
    errno = EIO;
    return -1;
  }
  return fsync(root->fd);
}

static bool actql_writer_name_matches(
  actql_native_filesystem_writer *writer,
  const char *name,
  bool final_name
) {
  const char *selected = final_name ? writer->final_name : writer->staging_name;
  return selected != NULL && strcmp(selected, name) == 0;
}

static int actql_close_writer_file(actql_native_filesystem_writer *writer) {
  if (writer->close_result != 0) return writer->close_result > 0 ? 0 : -1;
  if (writer->fd < 0) return 0;
  int descriptor = writer->fd;
  // Consume the original descriptor before the foreign close. No return path
  // may retry its integer or acknowledge an unconfirmed retirement.
  writer->fd = -1;
  writer->close_result = -1;
  if (close(descriptor) == 0) {
    writer->close_result = 1;
    return 0;
  }
  actql_replace_bounded_errno_error(&writer->close_error,
    writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "close writer", errno);
  return -1;
}

static int actql_remove_owned_name(
  actql_native_filesystem_writer *writer,
  const char *name,
  bool *present
) {
  if (!*present) return 0;
  struct stat status;
  if (fstatat(
        writer->root->fd,
        name,
        &status,
        AT_SYMLINK_NOFOLLOW
      ) != 0) {
    if (errno == ENOENT) {
      *present = false;
      return 0;
    }
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "inspect owned file", errno);
    return -1;
  }
  if (!S_ISREG(status.st_mode) || !actql_exact_generation(
        &status,
        writer->device,
        writer->inode,
        writer->written
      )) {
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "owned file generation changed");
    return 2;
  }
  if (unlinkat(writer->root->fd, name, 0) != 0) {
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "remove owned file", errno);
    return -1;
  }
  *present = false;
  return 0;
}

static void actql_native_filesystem_root_finalize(void *value) {
  actql_native_filesystem_root *root = value;
  // Finalization is not an observable retirement acknowledgement.
  if (root->census_stream != NULL) {
    closedir(root->census_stream);
    root->census_stream = NULL;
  }
  if (root->fd >= 0) {
    close(root->fd);
    root->fd = -1;
  }
  free(root->error);
  free(root->close_error);
  free(root->census_cleanup_error);
  free(root->namespace_cleanup_error);
  root->error = NULL;
  root->close_error = NULL;
  root->census_cleanup_error = NULL;
  root->namespace_cleanup_error = NULL;
  free(root->custody_path);
  root->custody_path = NULL;
}

// Closes this directory descriptor only. Readers/writers have their own
// retirement responsibility; this acknowledgement does not claim their stop.
int32_t actql_native_filesystem_root_close(
  actql_native_filesystem_root *root
) {
  if (root == NULL) return -1;
  if (root->close_result != 0) return root->close_result == 1 ? 0 : -1;
  if (root->census_stream != NULL ||
      (root->census_descriptor_acquired &&
       !root->census_descriptor_close_consumed)) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      "directory census is still active");
    return -1;
  }
  if (root->fd < 0) return -1;
  int descriptor = root->fd;
  root->fd = -1;
  root->close_result = -1;
  if (close(descriptor) != 0) {
    actql_replace_bounded_errno_error(&root->close_error, root->diagnostic_ceiling, "close Store root", errno);
    return -1;
  }
  if (root->census_cleanup_unconfirmed) {
    // The Root fd close does not acknowledge a consumed census descriptor.
    actql_replace_bounded_error(&root->close_error, root->diagnostic_ceiling,
      root->census_cleanup_error);
    return -1;
  }
  if (root->namespace_cleanup_unconfirmed) {
    actql_replace_bounded_error(&root->close_error, root->diagnostic_ceiling,
      root->namespace_cleanup_error);
    return -1;
  }
  root->close_result = 1;
  return 0;
}

static void actql_native_filesystem_lock_finalize(void *value) {
  actql_native_filesystem_lock *lock = value;
  if (lock->fd >= 0) {
    flock(lock->fd, LOCK_UN);
    close(lock->fd);
    lock->fd = -1;
  }
  free(lock->error);
  free(lock->close_error);
  lock->error = NULL;
  lock->close_error = NULL;
  if (lock->root != NULL) {
    moonbit_decref(lock->root);
    lock->root = NULL;
  }
}

static void actql_native_filesystem_writer_finalize(void *value) {
  actql_native_filesystem_writer *writer = value;
  (void)actql_close_writer_file(writer);
  // An unconfirmed close cannot authorize unlinking partial material. Keep
  // the original names for inspection even when this handle is dropped.
  if (!writer->preserve_names && writer->close_result >= 0 &&
      writer->root != NULL && writer->root->fd >= 0) {
    if (writer->final_present && writer->final_name != NULL &&
        (!writer->sealed || writer->cleanup_requested)) {
      struct stat status;
      if (actql_stat_regular_at(writer->root, writer->final_name, &status) &&
          actql_exact_generation(
            &status,
            writer->device,
            writer->inode,
            writer->written
          )) {
        unlinkat(writer->root->fd, writer->final_name, 0);
      }
    }
    if (writer->staging_present && writer->staging_name != NULL) {
      struct stat status;
      if (actql_stat_regular_at(writer->root, writer->staging_name, &status) &&
          actql_exact_generation(
            &status,
            writer->device,
            writer->inode,
            writer->written
          )) {
        unlinkat(writer->root->fd, writer->staging_name, 0);
      }
    }
  }
  free(writer->staging_name);
  free(writer->final_name);
  free(writer->error);
  free(writer->close_error);
  writer->staging_name = NULL;
  writer->final_name = NULL;
  writer->error = NULL;
  writer->close_error = NULL;
  if (writer->root != NULL) {
    moonbit_decref(writer->root);
    writer->root = NULL;
  }
}

static void actql_native_filesystem_reader_finalize(void *value) {
  actql_native_filesystem_reader *reader = value;
  if (reader->fd >= 0) {
    close(reader->fd);
    reader->fd = -1;
  }
  free(reader->error);
  free(reader->close_error);
  free(reader->chunk);
  reader->error = NULL;
  reader->close_error = NULL;
  reader->chunk = NULL;
  if (reader->root != NULL) {
    moonbit_decref(reader->root);
    reader->root = NULL;
  }
}

void *actql_native_filesystem_open_root_with_diagnostics(
  moonbit_bytes_t path,
  int32_t length,
  int32_t diagnostic_ceiling
) {
  actql_native_filesystem_root *root = moonbit_make_external_object(
    actql_native_filesystem_root_finalize,
    sizeof(actql_native_filesystem_root)
  );
  memset(root, 0, sizeof(*root));
  root->fd = -1;
  // This entrance has acquired no descriptor yet. Failed open/allocation
  // retires no child and must not fabricate a close attempt.
  root->close_result = 1;
  root->diagnostic_ceiling = diagnostic_ceiling;
  if (diagnostic_ceiling < 0) return root;
  char *path_text = actql_copy_text(path, length);
  if (path_text == NULL) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "root path allocation failed");
    return root;
  }
  root->fd = open(path_text, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  int open_error = errno;
  if (root->fd >= 0) root->close_result = 0;
  if (length > 1 && length <= 4096 && path_text[0] == '/' &&
      (int32_t)strlen(path_text) == length) {
    root->custody_path = strdup(path_text);
  }
  free(path_text);
  if (root->fd < 0) {
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "open Store root", open_error);
  }
  return root;
}

// Existing C callers retain their original ABI and unselected diagnostic path.
void *actql_native_filesystem_open_root(moonbit_bytes_t path, int32_t length) {
  return actql_native_filesystem_open_root_with_diagnostics(path, length, 0);
}

int32_t actql_native_filesystem_root_ready(
  actql_native_filesystem_root *root
) {
  return root != NULL && root->fd >= 0;
}

#include "command_acl.inc"

// Private Host state refuses access ACLs as well as broad POSIX mode bits.
// Existing general Store-root opening retains its original behavior.
static bool actql_private_root_acl(int fd) {
#ifdef __APPLE__
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (actql_native_command_platform_current() != NULL)
    return actql_command_acl_bounded(fd, false);
#endif
  acl_t acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED);
  // On a live descriptor Darwin reports an absent extended ACL as ENOENT.
  // Retrieval failures other than this explicit absence remain refusals.
  if (acl == NULL) return errno == ENOENT;
  if (acl_valid(acl) != 0) { acl_free(acl); return false; }
  acl_entry_t entry;
  int result = acl_get_entry(acl, ACL_FIRST_ENTRY, &entry);
  int entry_error = errno;
  acl_free(acl);
  // Darwin returns zero for an entry, and EINVAL at the end of a valid ACL.
  return result == -1 && entry_error == EINVAL;
#elif defined(__linux__)
  const char *names[] = {"system.posix_acl_access", "system.posix_acl_default"};
  for (size_t index = 0; index < 2; index++) {
    ssize_t size = fgetxattr(fd, names[index], NULL, 0);
    if (size >= 0 || (errno != ENODATA && errno != ENOTSUP)) return false;
  }
  return true;
#else
  // An unsupported physical privacy check never becomes a permit.
  (void)fd;
  return false;
#endif
}

// A bounded descriptor walk rechecks the selected name, not just a still-open
// descriptor of a directory removed or replaced since the original opening.
static int actql_open_contained_directory(char *text) {
  size_t length = strlen(text);
  if (length <= 1 || length > 4096 || text[0] != '/' ||
      text[length - 1] == '/') { errno = EINVAL; return -1; }
  int current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  char *component = text + 1;
  while (current >= 0 && *component != '\0') {
    char *end = strchr(component, '/');
    if (end != NULL) *end = '\0';
    if (*component == '\0' || strcmp(component, ".") == 0 ||
        strcmp(component, "..") == 0) {
      close(current);
      errno = EINVAL;
      return -1;
    }
    int next = openat(current, component,
      O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    int open_error = errno;
    close(current);
    current = next;
    errno = open_error;
    if (end == NULL) break;
    component = end + 1;
  }
  return current;
}

static bool actql_package_namespace_close(actql_native_filesystem_root *, int);
static int actql_package_namespace_walk(actql_native_filesystem_root *);

static bool actql_private_root_namespace(
  actql_native_filesystem_root *root,
  const struct stat *original
) {
  if (root->namespace_cleanup_unconfirmed) return false;
  int descriptor = actql_package_namespace_walk(root);
  if (descriptor < 0) return false;
  struct stat current;
  bool matches = fstat(descriptor, &current) == 0 &&
    current.st_dev == original->st_dev && current.st_ino == original->st_ino &&
    current.st_nlink > 0 && current.st_uid == geteuid() &&
    (current.st_mode & 0777) == 0700;
  return actql_package_namespace_close(root, descriptor) && matches;
}

// Existing observed namespace walk, shared by package and private-current
// observations. Every temporary close retains Unknown on the same Root.
static bool actql_package_namespace_close(
  actql_native_filesystem_root *root, int descriptor
) {
  int result = close(descriptor), error_number = errno;
  if (root->test_namespace_close_failures > 0) {
    root->test_namespace_close_failures--;
    result = -1; error_number = EIO;
  }
  if (result == 0) return true;
  if (!root->namespace_cleanup_unconfirmed) {
    root->namespace_cleanup_unconfirmed = true;
    actql_replace_bounded_errno_error(&root->namespace_cleanup_error,
      root->diagnostic_ceiling, "close package namespace observation", error_number);
  }
  actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
    root->namespace_cleanup_error);
  return false;
}

static int actql_package_namespace_walk(actql_native_filesystem_root *root) {
  if (root->custody_path == NULL) return -1;
  size_t length = strlen(root->custody_path);
  if (length <= 1 || length > 4096 || root->custody_path[0] != '/' ||
      root->custody_path[length - 1] == '/') return -1;
  char *text = strdup(root->custody_path);
  if (text == NULL) return -1;
  // Validate the whole selected original path before acquiring any descriptor.
  for (char *part = text + 1; *part != '\0';) {
    char *end = strchr(part, '/');
    size_t size = end == NULL ? strlen(part) : (size_t)(end - part);
    if (size == 0 || (size == 1 && part[0] == '.') ||
        (size == 2 && part[0] == '.' && part[1] == '.')) {free(text); return -1;}
    if (end == NULL) break;
    part = end + 1;
  }
  int current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  for (char *part = text + 1; current >= 0 && *part != '\0';) {
    char *end = strchr(part, '/');
    if (end != NULL) *end = '\0';
    int next = openat(current, part, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (!actql_package_namespace_close(root, current)) {
      if (next >= 0) actql_package_namespace_close(root, next);
      free(text); return -2;
    }
    current = next;
    if (end == NULL) break;
    part = end + 1;
  }
  free(text);
  return current;
}

static bool actql_observed_directory_matches(
  actql_native_observed_directory_stat *original, const struct stat *current
) {
  return S_ISDIR(current->st_mode) && current->st_nlink > 0 &&
    (uint64_t)current->st_dev == original->device &&
    (uint64_t)current->st_ino == original->inode && current->st_mode == original->mode &&
    current->st_uid == original->uid && current->st_gid == original->gid;
}

static int32_t actql_directory_observation_current(
  actql_native_filesystem_root *root, actql_native_observed_directory_stat *original
) {
  if (root == NULL || original == NULL || original->issue_kind != 0)
    return 1;
  if (root->census_cleanup_unconfirmed || root->namespace_cleanup_unconfirmed) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      root->census_cleanup_unconfirmed ? root->census_cleanup_error : root->namespace_cleanup_error);
    return 3;
  }
  if (root->fd < 0) return 1;
  struct stat opened;
  if (fstat(root->fd, &opened) != 0 || !actql_observed_directory_matches(original, &opened))
    return 1;
  int descriptor = actql_package_namespace_walk(root);
  if (descriptor == -2) return 3;
  if (descriptor < 0) return 1;
  struct stat named;
  bool matches = fstat(descriptor, &named) == 0 && actql_observed_directory_matches(original, &named);
  if (!actql_package_namespace_close(root, descriptor)) return 3;
  return matches ? 0 : 1;
}

static void actql_observed_directory_stat_finalize(void *value) {
  (void)value;
}

void *actql_native_filesystem_observe_directory(actql_native_filesystem_root *root) {
  actql_native_observed_directory_stat *observation = moonbit_make_external_object(
    actql_observed_directory_stat_finalize, sizeof(*observation));
  memset(observation, 0, sizeof(*observation));
  observation->issue_kind = 1;
  if (root == NULL) return observation;
  if (root->census_cleanup_unconfirmed || root->namespace_cleanup_unconfirmed) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      root->census_cleanup_unconfirmed ? root->census_cleanup_error : root->namespace_cleanup_error);
    observation->issue_kind = 3;
    return observation;
  }
  if (root->fd < 0) return observation;
  struct stat original;
  if (fstat(root->fd, &original) != 0 || !S_ISDIR(original.st_mode) || original.st_nlink == 0)
    return observation;
  observation->device = (uint64_t)original.st_dev;
  observation->inode = (uint64_t)original.st_ino;
  observation->mode = original.st_mode;
  observation->uid = original.st_uid;
  observation->gid = original.st_gid;
  observation->issue_kind = 0;
  observation->issue_kind = actql_directory_observation_current(root, observation);
  return observation;
}

int32_t actql_native_filesystem_observed_directory_kind(actql_native_observed_directory_stat *value) {
  return value == NULL ? 1 : value->issue_kind;
}

int32_t actql_native_filesystem_observed_directory_current(
  actql_native_filesystem_root *root, actql_native_observed_directory_stat *original
) {
  return actql_directory_observation_current(root, original);
}

uint64_t actql_native_filesystem_observed_directory_device(
  actql_native_observed_directory_stat *value
) {
  return value->device;
}

uint64_t actql_native_filesystem_observed_directory_inode(
  actql_native_observed_directory_stat *value
) {
  return value->inode;
}

void actql_native_filesystem_test_namespace_close_failure(
  actql_native_filesystem_root *root, int32_t count
) {
  if (root != NULL) root->test_namespace_close_failures = count;
}

int32_t actql_native_filesystem_test_directory_replacement(actql_native_filesystem_root *root) {
  if (root == NULL || root->fd < 0 || root->custody_path == NULL) return 0;
  size_t size = strlen(root->custody_path);
  if (size > 4096 - 6) return 0;
  char *moved = malloc(size + 7);
  if (moved == NULL) return 0;
  snprintf(moved, size + 7, "%s.moved", root->custody_path);
  int renamed = rename(root->custody_path, moved);
  free(moved);
  return renamed == 0 && mkdir(root->custody_path, 0755) == 0;
}

// A bootstrap parent is not private state: ordinary HOME mode bits and a
// valid deny-only Darwin ACL may restrict access without granting other users
// mutation rights. Any allow entry or failed ACL observation remains a refusal.
static bool actql_bootstrap_parent_acl(int fd) {
#ifdef __APPLE__
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (actql_native_command_platform_current() != NULL)
    return actql_command_acl_bounded(fd, true);
#endif
  acl_t acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED);
  if (acl == NULL) return errno == ENOENT;
  bool trusted = acl_valid(acl) == 0;
  acl_entry_t entry;
  int selector = ACL_FIRST_ENTRY;
  size_t count = 0;
  while (trusted) {
    int result = acl_get_entry(acl, selector, &entry);
    if (result == -1 && errno == EINVAL) break;
    acl_tag_t tag;
    if (result != 0 || ++count > 128 ||
        acl_get_tag_type(entry, &tag) != 0 || tag != ACL_EXTENDED_DENY) {
      trusted = false;
      break;
    }
    selector = ACL_NEXT_ENTRY;
  }
  return acl_free(acl) == 0 && trusted;
#else
  // POSIX ACLs are conservatively refused; the ordinary mode-only HOME works.
  return actql_private_root_acl(fd);
#endif
}

static bool actql_bootstrap_parent_status(const struct stat *status) {
  return S_ISDIR(status->st_mode) && status->st_nlink > 0 &&
    status->st_uid == geteuid() && (status->st_mode & 0700) == 0700 &&
    (status->st_mode & 0022) == 0;
}

int32_t actql_native_filesystem_bootstrap_parent_identity(
  actql_native_filesystem_root *root
) {
  if (root == NULL) return 0;
  root->result_device = 0;
  root->result_inode = 0;
  if (root->fd < 0 || root->custody_path == NULL) return 0;
  struct stat original;
  if (fstat(root->fd, &original) != 0 ||
      !actql_bootstrap_parent_status(&original) ||
      !actql_bootstrap_parent_acl(root->fd)) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "Bootstrap parent is not trusted");
    return 0;
  }
  char *copy = strdup(root->custody_path);
  if (copy == NULL) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "Bootstrap parent custody allocation failed");
    return 0;
  }
  int descriptor = actql_open_contained_directory(copy);
  free(copy);
  if (descriptor < 0) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "Bootstrap parent namespace is unavailable");
    return 0;
  }
  struct stat current;
  bool trusted = fstat(descriptor, &current) == 0 &&
    current.st_dev == original.st_dev && current.st_ino == original.st_ino &&
    actql_bootstrap_parent_status(&current) && actql_bootstrap_parent_acl(descriptor);
  bool closed = close(descriptor) == 0;
  if (!trusted || !closed) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "Bootstrap parent namespace changed");
    return 0;
  }
  root->result_device = (uint64_t)original.st_dev;
  root->result_inode = (uint64_t)original.st_ino;
  return 1;
}

int32_t actql_native_filesystem_private_root_identity(
  actql_native_filesystem_root *root
) {
  if (root == NULL || root->fd < 0) return 0;
  if (root->namespace_cleanup_unconfirmed) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      root->namespace_cleanup_error);
    return 0;
  }
  root->result_device = 0;
  root->result_inode = 0;
  struct stat status;
  if (fstat(root->fd, &status) != 0) {
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "inspect private Host root", errno);
    return 0;
  }
  if (!S_ISDIR(status.st_mode) || status.st_nlink == 0 || status.st_uid != geteuid() ||
      (status.st_mode & 0777) != 0700 || !actql_private_root_acl(root->fd)) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "Host root is not user-owned and private");
    return 0;
  }
  if (!actql_private_root_namespace(root, &status)) {
    if (!root->namespace_cleanup_unconfirmed)
      actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
        "Host root is not user-owned and private");
    return 0;
  }
  root->result_device = (uint64_t)status.st_dev;
  root->result_inode = (uint64_t)status.st_ino;
  return 1;
}

void *actql_native_filesystem_open_private_root_with_diagnostics(
  moonbit_bytes_t path,
  int32_t length,
  int32_t diagnostic_ceiling
) {
  actql_native_filesystem_root *root = moonbit_make_external_object(
    actql_native_filesystem_root_finalize,
    sizeof(actql_native_filesystem_root)
  );
  memset(root, 0, sizeof(*root));
  root->fd = -1;
  // No descriptor has been acquired. Failed validation/open may retire only
  // this rejected constructor; it must not fabricate a physical close.
  root->close_result = 1;
  root->diagnostic_ceiling = diagnostic_ceiling;
  if (diagnostic_ceiling < 0) return root;
  if (length <= 1 || length > 4096) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "invalid private Host root path");
    return root;
  }
  char *text = actql_copy_text(path, length);
  if (text == NULL) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "root path allocation failed");
    return root;
  }
  if (text[0] != '/' || text[length - 1] == '/' ||
      (int32_t)strlen(text) != length) {
    free(text);
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "invalid private Host root path");
    return root;
  }
  root->custody_path = strdup(text);
  if (root->custody_path == NULL) {
    free(text);
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "root custody allocation failed");
    return root;
  }
  // Walk pinned descriptors: no component may follow a symlink or interpret
  // dot/dot-dot as a containment escape. The supplied path remains unchanged.
  root->fd = actql_open_contained_directory(text);
  int open_error = errno;
  if (root->fd >= 0) root->close_result = 0;
  free(text);
  if (root->fd < 0) {
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "open private Host root", open_error);
  } else if (!actql_native_filesystem_private_root_identity(root)) {
    // Retain the original close outcome separately from the privacy refusal.
    // An unconfirmed consumed fd must never be closed again by its number.
    actql_native_filesystem_root_close(root);
  }
  return root;
}

// Custody entrance uses the same Root, privacy predicate and existing observed
// walk. Early path/namespace close Unknown cannot become a no-FD cleanup ACK.
void *actql_native_filesystem_open_private_root_with_custody_diagnostics(
  moonbit_bytes_t path, int32_t length, int32_t diagnostic_ceiling
) {
  actql_native_filesystem_root *root = moonbit_make_external_object(
    actql_native_filesystem_root_finalize, sizeof(actql_native_filesystem_root));
  memset(root, 0, sizeof(*root)); root->fd = -1; root->close_result = 1;
  root->diagnostic_ceiling = diagnostic_ceiling;
  if (diagnostic_ceiling < 0) return root;
  if (length <= 1 || length > 4096) {
    actql_replace_bounded_error(&root->error, diagnostic_ceiling, "invalid private Host root path");
    return root;
  }
  char *text = actql_copy_text(path, length);
  if (text == NULL) {
    actql_replace_bounded_error(&root->error, diagnostic_ceiling, "root path allocation failed");
    return root;
  }
  if (text[0] != '/' || text[length - 1] == '/' || (int32_t)strlen(text) != length) {
    free(text);
    actql_replace_bounded_error(&root->error, diagnostic_ceiling, "invalid private Host root path");
    return root;
  }
  root->custody_path = text;
  int descriptor = actql_package_namespace_walk(root), open_error = errno;
  if (descriptor < 0) {
    if (root->namespace_cleanup_unconfirmed) {
      root->close_result = -1;
      actql_replace_bounded_error(&root->close_error, diagnostic_ceiling,
        root->namespace_cleanup_error);
    } else actql_replace_bounded_errno_error(&root->error, diagnostic_ceiling,
      "open private Host root", open_error);
    return root;
  }
  root->fd = descriptor; root->close_result = 0;
  if (!actql_native_filesystem_private_root_identity(root))
    actql_native_filesystem_root_close(root);
  return root;
}

void *actql_native_filesystem_open_private_root(
  moonbit_bytes_t path, int32_t length
) {
  return actql_native_filesystem_open_private_root_with_diagnostics(path, length, 0);
}

static void actql_observed_file_stat_finalize(void *value) {
  // The existing Moon object owns only stat bytes, no descriptor or new Owner.
  (void)value;
}

static bool actql_observed_file_matches(
  const struct stat *original, const struct stat *current
) {
  if (!S_ISREG(current->st_mode) || current->st_nlink == 0 ||
      original->st_dev != current->st_dev || original->st_ino != current->st_ino ||
      original->st_mode != current->st_mode || original->st_uid != current->st_uid ||
      original->st_gid != current->st_gid || original->st_nlink != current->st_nlink ||
      original->st_size != current->st_size) return false;
#ifdef __APPLE__
  return original->st_mtimespec.tv_sec == current->st_mtimespec.tv_sec &&
    original->st_mtimespec.tv_nsec == current->st_mtimespec.tv_nsec &&
    original->st_ctimespec.tv_sec == current->st_ctimespec.tv_sec &&
    original->st_ctimespec.tv_nsec == current->st_ctimespec.tv_nsec;
#elif defined(__linux__)
  return original->st_mtim.tv_sec == current->st_mtim.tv_sec &&
    original->st_mtim.tv_nsec == current->st_mtim.tv_nsec &&
    original->st_ctim.tv_sec == current->st_ctim.tv_sec &&
    original->st_ctim.tv_nsec == current->st_ctim.tv_nsec;
#else
  return false;
#endif
}

static bool actql_observed_file_root_matches(
  actql_native_filesystem_root *root, actql_native_observed_file_stat *original
) {
  if (root == NULL || root->fd < 0 || original == NULL || original->issue_kind != 0 ||
      root->census_cleanup_unconfirmed || root->namespace_cleanup_unconfirmed) return false;
  struct stat current;
  return fstat(root->fd, &current) == 0 && S_ISDIR(current.st_mode) &&
    current.st_nlink > 0 && (uint64_t)current.st_dev == original->root_device &&
    (uint64_t)current.st_ino == original->root_inode;
}

void *actql_native_filesystem_observe_file(
  actql_native_filesystem_root *root, moonbit_bytes_t name, int32_t length
) {
  actql_native_observed_file_stat *observation = moonbit_make_external_object(
    actql_observed_file_stat_finalize, sizeof(*observation));
  memset(observation, 0, sizeof(*observation));
  observation->issue_kind = 1;
  if (root == NULL || root->fd < 0) return observation;
  if (root->census_cleanup_unconfirmed || root->namespace_cleanup_unconfirmed) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      root->census_cleanup_unconfirmed ? root->census_cleanup_error : root->namespace_cleanup_error);
    observation->issue_kind = 3;
    return observation;
  }
  char *text = actql_copy_text(name, length);
  if (text == NULL || length <= 0 || !actql_valid_name(text, (size_t)length)) {
    free(text); return observation;
  }
  struct stat parent;
  bool captured = fstat(root->fd, &parent) == 0 && S_ISDIR(parent.st_mode) &&
    parent.st_nlink > 0 && actql_stat_regular_at(root, text, &observation->original);
  free(text);
  if (!captured || observation->original.st_nlink == 0) return observation;
  observation->root_device = (uint64_t)parent.st_dev;
  observation->root_inode = (uint64_t)parent.st_ino;
  observation->issue_kind = 0;
  return observation;
}

int32_t actql_native_filesystem_observed_file_kind(actql_native_observed_file_stat *value) {
  return value == NULL ? 1 : value->issue_kind;
}
uint64_t actql_native_filesystem_observed_file_device(actql_native_observed_file_stat *value) {
  return (uint64_t)value->original.st_dev;
}
uint64_t actql_native_filesystem_observed_file_inode(actql_native_observed_file_stat *value) {
  return (uint64_t)value->original.st_ino;
}
int64_t actql_native_filesystem_observed_file_size(actql_native_observed_file_stat *value) {
  return (int64_t)value->original.st_size;
}
int32_t actql_native_filesystem_observed_file_mode(actql_native_observed_file_stat *value) {
  return (int32_t)(value->original.st_mode & 07777);
}

int32_t actql_native_filesystem_observed_file_current(
  actql_native_filesystem_root *root, moonbit_bytes_t name, int32_t length,
  actql_native_observed_file_stat *original
) {
  if (root != NULL && (root->census_cleanup_unconfirmed || root->namespace_cleanup_unconfirmed)) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling,
      root->census_cleanup_unconfirmed ? root->census_cleanup_error : root->namespace_cleanup_error);
    return 3;
  }
  if (!actql_observed_file_root_matches(root, original)) return 1;
  char *text = actql_copy_text(name, length);
  if (text == NULL || length <= 0 || !actql_valid_name(text, (size_t)length)) {
    free(text); return 1;
  }
  struct stat current;
  bool matches = actql_stat_regular_at(root, text, &current) &&
    actql_observed_file_matches(&original->original, &current);
  free(text);
  return matches ? 0 : 1;
}

int32_t actql_native_filesystem_observed_file_reader(
  actql_native_filesystem_root *root, actql_native_filesystem_reader *reader,
  actql_native_observed_file_stat *original
) {
  if (!actql_observed_file_root_matches(root, original) || reader == NULL ||
      reader->root != root || reader->fd < 0 || !reader->ready) return 0;
  struct stat opened;
  return fstat(reader->fd, &opened) == 0 &&
    actql_observed_file_matches(&original->original, &opened);
}

int32_t actql_native_filesystem_test_observation_mutation(
  actql_native_filesystem_root *root, moonbit_bytes_t name, int32_t length,
  int32_t kind
) {
  if (root == NULL || root->fd < 0 || (kind != 1 && kind != 2)) return 0;
  char *text = actql_copy_text(name, length);
  if (text == NULL || !actql_valid_name(text, (size_t)length)) {free(text); return 0;}
  int descriptor = openat(root->fd, text, O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  free(text);
  if (descriptor < 0) return 0;
  struct stat stat;
  bool valid = fstat(descriptor, &stat) == 0 && S_ISREG(stat.st_mode) && stat.st_size == 3;
  bool changed = false;
  if (valid) {
    changed = kind == 1 ? fchmod(descriptor, 0600) == 0 : pwrite(descriptor, "xyz", 3, 0) == 3;
  }
  return close(descriptor) == 0 && changed;
}

static bool actql_private_file_same_generation(
  const struct stat *original,
  const struct stat *opened
) {
  if (!S_ISREG(opened->st_mode) || opened->st_uid != geteuid() ||
      (opened->st_mode & 077) != 0 || opened->st_nlink != 1 ||
      original->st_dev != opened->st_dev ||
      original->st_ino != opened->st_ino ||
      original->st_mode != opened->st_mode ||
      original->st_uid != opened->st_uid ||
      original->st_gid != opened->st_gid ||
      original->st_size != opened->st_size) return false;
#ifdef __APPLE__
  return original->st_mtimespec.tv_sec == opened->st_mtimespec.tv_sec &&
    original->st_mtimespec.tv_nsec == opened->st_mtimespec.tv_nsec &&
    original->st_ctimespec.tv_sec == opened->st_ctimespec.tv_sec &&
    original->st_ctimespec.tv_nsec == opened->st_ctimespec.tv_nsec;
#else
  return original->st_mtim.tv_sec == opened->st_mtim.tv_sec &&
    original->st_mtim.tv_nsec == opened->st_mtim.tv_nsec &&
    original->st_ctim.tv_sec == opened->st_ctim.tv_sec &&
    original->st_ctim.tv_nsec == opened->st_ctim.tv_nsec;
#endif
}

static void actql_private_file_projection_finalize(void *value) {
  actql_native_private_file_projection *projection = value;
  free(projection->name);
  projection->name = NULL;
  if (projection->root != NULL) {
    moonbit_decref(projection->root);
    projection->root = NULL;
  }
}

void *actql_native_filesystem_adopt_private_file_projection(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length
) {
  actql_native_private_file_projection *projection = moonbit_make_external_object(
    actql_private_file_projection_finalize, sizeof(*projection)
  );
  memset(projection, 0, sizeof(*projection));
  projection->root = root;
  if (root != NULL) moonbit_incref(root);
  projection->name = actql_copy_text(name, length);
  if (projection->name == NULL || length <= 0 ||
      !actql_valid_name(projection->name, (size_t)length) ||
      !actql_native_filesystem_private_root_identity(root) ||
      !actql_stat_regular_at(root, projection->name, &projection->original) ||
      projection->original.st_size <= 0 || projection->original.st_size > 8192 ||
      !actql_private_file_same_generation(
        &projection->original, &projection->original
      )) return projection;
  projection->original_root_device = root->result_device;
  projection->original_root_inode = root->result_inode;
  projection->ready = true;
  return projection;
}

int32_t actql_native_filesystem_private_file_projection_ready(
  actql_native_private_file_projection *projection
) {
  return projection != NULL && projection->ready;
}

bool actql_native_private_file_projection_matches(
  actql_native_private_file_projection *projection,
  int descriptor
) {
  struct stat opened, named;
  return projection != NULL && projection->ready && descriptor >= 0 &&
    actql_native_filesystem_private_root_identity(projection->root) &&
    projection->root->result_device == projection->original_root_device &&
    projection->root->result_inode == projection->original_root_inode &&
    fstat(descriptor, &opened) == 0 &&
    actql_private_file_same_generation(&projection->original, &opened) &&
    actql_stat_regular_at(projection->root, projection->name, &named) &&
    actql_private_file_same_generation(&projection->original, &named);
}

bool actql_native_private_file_projection_open_with_custody(
  actql_native_private_file_projection *projection, int *descriptor
) {
  if (descriptor == NULL || *descriptor != -1 || projection == NULL ||
      !projection->ready ||
      !actql_native_filesystem_private_root_identity(projection->root)) return false;
  *descriptor = openat(
    projection->root->fd, projection->name,
    O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
  );
  return actql_native_private_file_projection_matches(projection, *descriptor);
}

int actql_native_private_file_projection_open(
  actql_native_private_file_projection *projection
) {
  int descriptor = -1;
  if (!actql_native_private_file_projection_open_with_custody(projection, &descriptor)) {
    if (descriptor >= 0) close(descriptor);
    return -1;
  }
  return descriptor;
}

// Private format: AQLPFP01, platform byte, name length, twelve big-endian
// 64-bit fields, then the exact object name. No struct layout, secret, pointer,
// public identity or authorization is encoded. The Host must authenticate and
// bind these original bytes through its existing private journal custody.
#define ACTQL_PRIVATE_PROJECTION_PREFIX 106
#define ACTQL_PRIVATE_PROJECTION_MAX 234
#ifdef __APPLE__
#define ACTQL_PRIVATE_PROJECTION_PLATFORM 1
#elif defined(__linux__)
#define ACTQL_PRIVATE_PROJECTION_PLATFORM 2
#else
#define ACTQL_PRIVATE_PROJECTION_PLATFORM 0
#endif

static void actql_projection_put(unsigned char *output, uint64_t value) {
  for (int index = 7; index >= 0; index--) {
    output[index] = (unsigned char)(value & 255);
    value >>= 8;
  }
}

static uint64_t actql_projection_get(const unsigned char *input) {
  uint64_t value = 0;
  for (int index = 0; index < 8; index++) value = (value << 8) | input[index];
  return value;
}

static int64_t actql_projection_signed(uint64_t value) {
  return value <= INT64_MAX ? (int64_t)value : -1 - (int64_t)(UINT64_MAX - value);
}

static void actql_projection_fields(
  const actql_native_private_file_projection *projection, uint64_t fields[12]
) {
  const struct stat *file = &projection->original;
  fields[0] = projection->original_root_device;
  fields[1] = projection->original_root_inode;
  fields[2] = (uint64_t)file->st_dev;
  fields[3] = (uint64_t)file->st_ino;
  fields[4] = (uint64_t)file->st_mode;
  fields[5] = (uint64_t)file->st_uid;
  fields[6] = (uint64_t)file->st_gid;
  fields[7] = (uint64_t)file->st_size;
#ifdef __APPLE__
  fields[8] = (uint64_t)file->st_mtimespec.tv_sec;
  fields[9] = (uint64_t)file->st_mtimespec.tv_nsec;
  fields[10] = (uint64_t)file->st_ctimespec.tv_sec;
  fields[11] = (uint64_t)file->st_ctimespec.tv_nsec;
#else
  fields[8] = (uint64_t)file->st_mtim.tv_sec;
  fields[9] = (uint64_t)file->st_mtim.tv_nsec;
  fields[10] = (uint64_t)file->st_ctim.tv_sec;
  fields[11] = (uint64_t)file->st_ctim.tv_nsec;
#endif
}

int32_t actql_native_filesystem_export_private_file_projection(
  actql_native_private_file_projection *projection,
  moonbit_bytes_t output,
  int32_t capacity
) {
  if (projection == NULL || !projection->ready ||
      ACTQL_PRIVATE_PROJECTION_PLATFORM == 0) return 0;
  size_t name_length = strlen(projection->name);
  if (name_length == 0 || name_length > 128 ||
      capacity < ACTQL_PRIVATE_PROJECTION_PREFIX + (int32_t)name_length) return 0;
  int descriptor = actql_native_private_file_projection_open(projection);
  if (descriptor < 0 || close(descriptor) != 0) return 0;
  memcpy(output, "AQLPFP01", 8);
  output[8] = ACTQL_PRIVATE_PROJECTION_PLATFORM;
  output[9] = (unsigned char)name_length;
  uint64_t fields[12];
  actql_projection_fields(projection, fields);
  for (int index = 0; index < 12; index++) {
    actql_projection_put(output + 10 + index * 8, fields[index]);
  }
  memcpy(output + ACTQL_PRIVATE_PROJECTION_PREFIX, projection->name, name_length);
  return ACTQL_PRIVATE_PROJECTION_PREFIX + (int32_t)name_length;
}

void *actql_native_filesystem_restore_private_file_projection(
  actql_native_filesystem_root *root,
  moonbit_bytes_t original,
  int32_t length
) {
  actql_native_private_file_projection *projection = moonbit_make_external_object(
    actql_private_file_projection_finalize, sizeof(*projection)
  );
  memset(projection, 0, sizeof(*projection));
  projection->root = root;
  if (root != NULL) moonbit_incref(root);
  if (length <= ACTQL_PRIVATE_PROJECTION_PREFIX ||
      length > ACTQL_PRIVATE_PROJECTION_MAX ||
      memcmp(original, "AQLPFP01", 8) != 0 ||
      ACTQL_PRIVATE_PROJECTION_PLATFORM == 0 ||
      original[8] != ACTQL_PRIVATE_PROJECTION_PLATFORM || original[9] == 0 ||
      original[9] > 128 || length != ACTQL_PRIVATE_PROJECTION_PREFIX + original[9]) {
    return projection;
  }
  projection->name = actql_copy_text(original + ACTQL_PRIVATE_PROJECTION_PREFIX, original[9]);
  if (projection->name == NULL ||
      !actql_valid_name(projection->name, original[9])) return projection;
  uint64_t fields[12];
  for (int index = 0; index < 12; index++) {
    fields[index] = actql_projection_get(original + 10 + index * 8);
  }
  if (fields[7] == 0 || fields[7] > 8192 ||
      fields[9] >= 1000000000 || fields[11] >= 1000000000) return projection;
  projection->original_root_device = fields[0];
  projection->original_root_inode = fields[1];
  struct stat *file = &projection->original;
  file->st_dev = (dev_t)fields[2];
  file->st_ino = (ino_t)fields[3];
  file->st_mode = (mode_t)fields[4];
  file->st_uid = (uid_t)fields[5];
  file->st_gid = (gid_t)fields[6];
  file->st_size = (off_t)fields[7];
#ifdef __APPLE__
  file->st_mtimespec.tv_sec = (time_t)actql_projection_signed(fields[8]);
  file->st_mtimespec.tv_nsec = (long)fields[9];
  file->st_ctimespec.tv_sec = (time_t)actql_projection_signed(fields[10]);
  file->st_ctimespec.tv_nsec = (long)fields[11];
#else
  file->st_mtim.tv_sec = (time_t)actql_projection_signed(fields[8]);
  file->st_mtim.tv_nsec = (long)fields[9];
  file->st_ctim.tv_sec = (time_t)actql_projection_signed(fields[10]);
  file->st_ctim.tv_nsec = (long)fields[11];
#endif
  // Reject narrowing and non-canonical representations before comparing the
  // current namespace. Restoring never adopts freshly observed generation.
  uint64_t round_trip[12];
  actql_projection_fields(projection, round_trip);
  for (int index = 0; index < 12; index++) {
    if (round_trip[index] != fields[index]) return projection;
  }
  projection->ready = true;
  int descriptor = actql_native_private_file_projection_open(projection);
  if (descriptor < 0 || close(descriptor) != 0) projection->ready = false;
  return projection;
}

// Whitebox tests alter only their already-open, user-owned scratch directory.
int32_t actql_native_filesystem_test_private_mode(
  actql_native_filesystem_root *root,
  int32_t mode
) {
  struct stat status;
  if (root == NULL || root->fd < 0 || fstat(root->fd, &status) != 0 ||
      status.st_uid != geteuid() || (mode != 0700 && mode != 0750)) return 0;
  return fchmod(root->fd, (mode_t)mode) == 0;
}

moonbit_bytes_t actql_native_filesystem_root_error(
  actql_native_filesystem_root *root
) {
  return actql_copy_diagnostic(root == NULL ? "invalid Store root" :
    root->close_result < 0 ? root->close_error : root->error,
    root == NULL ? 0 : root->diagnostic_ceiling);
}

// Constructor refusal is separate from a later/unconfirmed cleanup outcome.
// The same Root remains retained; this projection admits no usable directory.
moonbit_bytes_t actql_native_filesystem_root_acquisition_error(
  actql_native_filesystem_root *root
) {
  return actql_copy_diagnostic(root == NULL ? "invalid Store root" : root->error,
    root == NULL ? 0 : root->diagnostic_ceiling);
}

// Same opaque Lock close path for successful and rejected acquisition.
int32_t actql_native_filesystem_lock_close_checked(actql_native_filesystem_lock *lock);

void *actql_native_filesystem_acquire_lock(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length
) {
  actql_native_filesystem_lock *lock = moonbit_make_external_object(
    actql_native_filesystem_lock_finalize,
    sizeof(actql_native_filesystem_lock)
  );
  memset(lock, 0, sizeof(*lock));
  lock->fd = -1;
  lock->root = root;
  if (root != NULL) moonbit_incref(root);
  char *name_text = actql_copy_text(name, length);
  if (root == NULL || root->fd < 0) {
    actql_replace_bounded_error(&lock->error, root == NULL ? 0 : root->diagnostic_ceiling, "Store root is unavailable");
  } else if (name_text == NULL) {
    actql_replace_bounded_error(&lock->error, root == NULL ? 0 : root->diagnostic_ceiling, "lock name allocation failed");
  } else if (!actql_valid_name(name_text, (size_t)length)) {
    actql_replace_bounded_error(&lock->error, root == NULL ? 0 : root->diagnostic_ceiling, "invalid lock name");
  } else {
    lock->fd = openat(
      root->fd,
      name_text,
      O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
      0600
    );
    if (lock->fd < 0) {
      actql_replace_bounded_errno_error(&lock->error, root->diagnostic_ceiling, "open Store lock", errno);
    } else {
      struct stat status;
      int inspect_result = fstat(lock->fd, &status);
      if (inspect_result != 0 || !S_ISREG(status.st_mode)) {
        int inspect_error = inspect_result == 0 ? 0 : errno;
        actql_native_filesystem_lock_close_checked(lock);
        if (inspect_error == 0) {
          actql_replace_bounded_error(&lock->error, root == NULL ? 0 : root->diagnostic_ceiling, "Store lock is not regular");
        } else {
          actql_replace_bounded_errno_error(
            &lock->error,
            root->diagnostic_ceiling,
            "inspect Store lock",
            inspect_error
          );
        }
      } else if (flock(lock->fd, LOCK_EX | LOCK_NB) != 0) {
        int lock_error = errno;
        actql_native_filesystem_lock_close_checked(lock);
        actql_replace_bounded_errno_error(&lock->error, root->diagnostic_ceiling, "acquire Store lock", lock_error);
      } else {
        lock->ready = true;
      }
    }
  }
  free(name_text);
  return lock;
}

int32_t actql_native_filesystem_lock_ready(
  actql_native_filesystem_lock *lock
) {
  return lock != NULL && lock->ready && lock->fd >= 0;
}

moonbit_bytes_t actql_native_filesystem_lock_error(
  actql_native_filesystem_lock *lock
) {
  return actql_copy_diagnostic(lock == NULL ? "invalid Store lock" : lock->error,
    lock == NULL || lock->root == NULL ? 0 : lock->root->diagnostic_ceiling);
}

int32_t actql_native_filesystem_lock_close_checked(
  actql_native_filesystem_lock *lock
) {
  if (lock == NULL) return 0;
  if (lock->close_result != 0) return lock->close_result == 1;
  if (lock->fd < 0) {
    // No descriptor was acquired, or a constructor already observed its
    // retirement through this same function. This says nothing about Root.
    lock->close_result = 1;
    return 1;
  }
  int descriptor = lock->fd;
  lock->fd = -1;
  lock->ready = false;
  lock->close_result = -1;
  flock(descriptor, LOCK_UN);
  if (close(descriptor) != 0) {
    actql_replace_bounded_errno_error(&lock->close_error,
      lock->root == NULL ? 0 : lock->root->diagnostic_ceiling,
      "close Store lock", errno);
    return 0;
  }
  lock->close_result = 1;
  return 1;
}

moonbit_bytes_t actql_native_filesystem_lock_cleanup_error(
  actql_native_filesystem_lock *lock
) {
  return actql_copy_diagnostic(lock == NULL ? "invalid Store lock" : lock->close_error,
    lock == NULL || lock->root == NULL ? 0 : lock->root->diagnostic_ceiling);
}

// Retain the original Bool entrance's first-close/second-close behavior.
int32_t actql_native_filesystem_lock_close(
  actql_native_filesystem_lock *lock
) {
  if (lock == NULL || lock->fd < 0 || lock->close_result != 0) return 0;
  return actql_native_filesystem_lock_close_checked(lock);
}

// Whitebox loss of the retirement observation, not an injected kernel errno.
// The real descriptor is closed once; retry must never touch a reused FD.
int32_t actql_native_filesystem_test_lock_consumed_unknown(
  actql_native_filesystem_lock *lock
) {
  if (lock == NULL || lock->fd < 0 ||
      !actql_native_filesystem_lock_close_checked(lock)) return 0;
  lock->close_result = -1;
  actql_replace_bounded_error(&lock->close_error,
    lock->root == NULL ? 0 : lock->root->diagnostic_ceiling,
    "lock retirement observation unavailable");
  return 1;
}

void *actql_native_filesystem_create_writer(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length,
  int64_t max_bytes
) {
  actql_native_filesystem_writer *writer = moonbit_make_external_object(
    actql_native_filesystem_writer_finalize,
    sizeof(actql_native_filesystem_writer)
  );
  memset(writer, 0, sizeof(*writer));
  writer->fd = -1;
  writer->root = root;
  if (root != NULL) moonbit_incref(root);
  writer->max_bytes = max_bytes;
  writer->staging_name = actql_copy_text(name, length);
  if (root == NULL || root->fd < 0) {
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "Store root is unavailable");
    return writer;
  }
  if (writer->staging_name == NULL) {
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "staging name allocation failed");
    return writer;
  }
  if (!actql_valid_name(writer->staging_name, (size_t)length)) {
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "invalid staging name");
    return writer;
  }
  if (max_bytes < 0) {
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "negative writer limit");
    return writer;
  }
  writer->fd = openat(
    root->fd,
    writer->staging_name,
    O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW,
    0600
  );
  if (writer->fd < 0) {
    int create_error = errno;
    writer->create_conflict = create_error == EEXIST;
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "create staging file",
      create_error
    );
    return writer;
  }
  struct stat status;
  if (fstat(writer->fd, &status) != 0) {
    int stat_error = errno;
    // Retain the actual rejected constructor and descriptor. Its caller must
    // acknowledge that original close; unknown metadata cannot authorize unlink.
    writer->preserve_names = true;
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "inspect staging file", stat_error);
    return writer;
  }
  if (!S_ISREG(status.st_mode) || status.st_size != 0) {
    writer->preserve_names = true;
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "staging file is not empty and regular");
    return writer;
  }
  writer->device = (uint64_t)status.st_dev;
  writer->inode = (uint64_t)status.st_ino;
  writer->written = 0;
  writer->staging_present = true;
  writer->ready = true;
  return writer;
}

int32_t actql_native_filesystem_writer_ready(
  actql_native_filesystem_writer *writer
) {
  return writer != NULL && writer->ready;
}

int32_t actql_native_filesystem_writer_conflict(
  actql_native_filesystem_writer *writer
) {
  return writer != NULL && writer->create_conflict;
}

moonbit_bytes_t actql_native_filesystem_writer_error(
  actql_native_filesystem_writer *writer
) {
  return actql_copy_diagnostic(writer == NULL ? "invalid writer" :
    writer->close_result < 0 ? writer->close_error : writer->error,
    writer == NULL || writer->root == NULL ? 0 : writer->root->diagnostic_ceiling);
}

int32_t actql_native_filesystem_writer_append(
  actql_native_filesystem_writer *writer,
  moonbit_bytes_t chunk,
  int32_t length
) {
  if (writer == NULL || !writer->ready || writer->fd < 0 ||
      writer->final_name != NULL || writer->cleanup_requested ||
      writer->cancelled) {
    return 2;
  }
  if (length < 0 || writer->written > writer->max_bytes ||
      (int64_t)length > writer->max_bytes - writer->written) {
    return 1;
  }
  actql_replace_bounded_error(&writer->error,
    writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, NULL);
  int32_t offset = 0;
  while (offset < length) {
    ssize_t count = write(
      writer->fd,
      chunk + offset,
      (size_t)(length - offset)
    );
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) {
      int write_error = count == 0 ? EIO : errno;
      writer->written += offset;
      writer->cleanup_requested = true;
      actql_replace_bounded_errno_error(&writer->error,
        writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "write staging file", write_error);
      return -1;
    }
    offset += (int32_t)count;
  }
  writer->written += length;
  return 0;
}

int32_t actql_native_filesystem_writer_seal(
  actql_native_filesystem_writer *writer,
  moonbit_bytes_t name,
  int32_t length
) {
  if (writer != NULL && writer->close_result < 0) return -1;
  if (writer == NULL || !writer->ready || writer->cancelled ||
      writer->cleanup_requested) {
    return 3;
  }
  char *final_name = actql_copy_text(name, length);
  if (final_name == NULL) {
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "final name allocation failed");
    return -1;
  }
  if (!actql_valid_file_component(final_name, (size_t)length)) {
    free(final_name);
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "invalid final name");
    return -1;
  }
  if (writer->final_name == NULL) {
    writer->final_name = final_name;
  } else {
    bool matches = actql_writer_name_matches(writer, final_name, true);
    free(final_name);
    if (!matches) return 3;
  }
  actql_replace_bounded_error(&writer->error,
    writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, NULL);
  if (writer->sealed) return 0;

  if (writer->fd >= 0) {
    if (fsync(writer->fd) != 0) {
      actql_replace_bounded_errno_error(&writer->error,
        writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "sync staging file", errno);
      return -1;
    }
    struct stat status;
    if (fstat(writer->fd, &status) != 0) {
      actql_replace_bounded_errno_error(&writer->error,
        writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "inspect staging writer", errno);
      return -1;
    }
    if (!S_ISREG(status.st_mode) || status.st_size < 0 ||
        (uint64_t)status.st_dev != writer->device ||
        (uint64_t)status.st_ino != writer->inode ||
        (int64_t)status.st_size != writer->written) {
      actql_replace_bounded_error(&writer->error,
        writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "staging writer generation changed");
      return 2;
    }
    if (actql_close_writer_file(writer) != 0) return -1;
  }

  if (!writer->final_present) {
    if (!writer->staging_present) {
      actql_replace_bounded_error(&writer->error,
        writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "staging file is unavailable");
      return 2;
    }
    if (linkat(
          writer->root->fd,
          writer->staging_name,
          writer->root->fd,
          writer->final_name,
          0
        ) != 0) {
      if (errno == EEXIST) return 1;
      actql_replace_bounded_errno_error(&writer->error,
        writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "link committed file", errno);
      return -1;
    }
    writer->final_present = true;
  }

  struct stat final_status;
  if (fstatat(
        writer->root->fd,
        writer->final_name,
        &final_status,
        AT_SYMLINK_NOFOLLOW
      ) != 0) {
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "inspect committed file", errno);
    return -1;
  }
  if (!S_ISREG(final_status.st_mode) || !actql_exact_generation(
        &final_status,
        writer->device,
        writer->inode,
        writer->written
      )) {
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "committed file generation changed");
    return 2;
  }

  int remove_result = actql_remove_owned_name(
    writer,
    writer->staging_name,
    &writer->staging_present
  );
  if (remove_result != 0) return remove_result;
  if (actql_sync_root(writer->root) != 0) {
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "sync Store root", errno);
    return -1;
  }
  if (fstatat(
        writer->root->fd,
        writer->final_name,
        &final_status,
        AT_SYMLINK_NOFOLLOW
      ) != 0) {
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "recheck committed file", errno);
    return -1;
  }
  if (!S_ISREG(final_status.st_mode) || !actql_exact_generation(
        &final_status,
        writer->device,
        writer->inode,
        writer->written
      )) {
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "committed generation was not retained");
    return 2;
  }
  writer->sealed = true;
  return 0;
}

// Gives the open staging file a second name and drops its private one: the
// new name is linked exclusively (an existing file is a conflict and is never
// replaced), verified as the same generation, and only then is the private
// name removed and the root synchronized. 0 on success, 1 on conflict, 2 when
// the generation changed, 3 when the writer cannot be renamed, -1 otherwise.
int32_t actql_native_filesystem_writer_adopt_name(
  actql_native_filesystem_writer *writer,
  actql_native_filesystem_root *target,
  moonbit_bytes_t name,
  int32_t length
) {
  if (target == NULL || target->fd < 0) return 3;
  if (writer == NULL || !writer->ready || writer->cancelled ||
      writer->cleanup_requested || writer->sealed || writer->fd < 0 ||
      !writer->staging_present) {
    return 3;
  }
  char *adopted = actql_copy_text(name, length);
  if (adopted == NULL) {
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "adopted name allocation failed");
    return -1;
  }
  if (!actql_valid_name(adopted, (size_t)length) ||
      (target == writer->root && strcmp(adopted, writer->staging_name) == 0)) {
    free(adopted);
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "invalid adopted name");
    return -1;
  }
  actql_replace_bounded_error(&writer->error,
    writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, NULL);
  if (linkat(
        writer->root->fd,
        writer->staging_name,
        target->fd,
        adopted,
        0
      ) != 0) {
    int link_error = errno;
    free(adopted);
    if (link_error == EEXIST) return 1;
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "link adopted name", link_error);
    return -1;
  }
  struct stat status;
  if (fstatat(target->fd, adopted, &status, AT_SYMLINK_NOFOLLOW) != 0) {
    int stat_error = errno;
    unlinkat(target->fd, adopted, 0);
    free(adopted);
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "inspect adopted name", stat_error);
    return -1;
  }
  if (!S_ISREG(status.st_mode) || !actql_exact_generation(
        &status,
        writer->device,
        writer->inode,
        writer->written
      )) {
    unlinkat(target->fd, adopted, 0);
    free(adopted);
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "adopted name generation changed");
    return 2;
  }
  // The private name goes from its own root; from here the writer's names
  // live under the target root.
  actql_native_filesystem_root *origin = writer->root;
  char *private_name = writer->staging_name;
  bool private_present = writer->staging_present;
  int remove_result = actql_remove_owned_name(
    writer,
    private_name,
    &private_present
  );
  if (remove_result != 0) {
    // Both names stay; cleanup of either finds the same generation. The
    // adopted name is dropped again so the writer keeps one root.
    unlinkat(target->fd, adopted, 0);
    free(adopted);
    return remove_result;
  }
  free(private_name);
  writer->staging_name = adopted;
  if (target != origin) {
    moonbit_incref(target);
    writer->root = target;
    if (actql_sync_root(origin) != 0) {
      actql_replace_bounded_errno_error(&writer->error,
        writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "sync allocation root", errno);
      moonbit_decref(origin);
      return -1;
    }
    moonbit_decref(origin);
  }
  if (actql_sync_root(writer->root) != 0) {
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "sync Store root", errno);
    return -1;
  }
  return 0;
}

// Retire only this descriptor while retaining all owned names for inspection.
// No contents/seal/publication/whole-cleanup acknowledgement is issued here.
int32_t actql_native_filesystem_writer_close_retaining_files(
  actql_native_filesystem_writer *writer
) {
  if (writer == NULL) return 0;
  writer->preserve_names = true;
  writer->cleanup_requested = true;
  if (actql_close_writer_file(writer) != 0) return -1;
  if (writer->close_result != 0 &&
      (writer->root == NULL || writer->root->fd < 0)) {
    actql_replace_bounded_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "retained partial Store root is unavailable");
    return -1;
  }
  if (writer->close_result != 0 && actql_sync_root(writer->root) != 0) {
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "sync retained partial files", errno);
    return -1;
  }
  return 0;
}

int32_t actql_native_filesystem_writer_cancel(
  actql_native_filesystem_writer *writer
) {
  if (writer == NULL) return 0;
  if (writer->close_result < 0) return -1;
  if (!writer->ready) return 0;
  if (writer->cancelled) return 0;
  writer->cleanup_requested = true;
  writer->sealed = false;
  actql_replace_bounded_error(&writer->error,
    writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, NULL);
  if (actql_close_writer_file(writer) != 0) return -1;

  if (writer->final_name != NULL) {
    int result = actql_remove_owned_name(
      writer,
      writer->final_name,
      &writer->final_present
    );
    if (result != 0) return result;
  }
  int result = actql_remove_owned_name(
    writer,
    writer->staging_name,
    &writer->staging_present
  );
  if (result != 0) return result;
  if (actql_sync_root(writer->root) != 0) {
    actql_replace_bounded_errno_error(&writer->error,
      writer->root == NULL ? 0 : writer->root->diagnostic_ceiling, "sync Store root", errno);
    return -1;
  }
  writer->cancelled = true;
  return 0;
}

int64_t actql_native_filesystem_writer_written(
  actql_native_filesystem_writer *writer
) {
  return writer == NULL ? 0 : writer->written;
}

int32_t actql_native_filesystem_writer_sealed(
  actql_native_filesystem_writer *writer
) {
  return writer != NULL && writer->sealed;
}

int32_t actql_native_filesystem_writer_pending_cleanup(
  actql_native_filesystem_writer *writer
) {
  if (writer == NULL) return 0;
  if (writer->close_result < 0) return 1;
  if (writer->preserve_names && writer->fd >= 0) return 1;
  if (!writer->ready || writer->cancelled) return 0;
  if (writer->cleanup_requested) {
    return writer->staging_present || writer->final_present;
  }
  return !writer->sealed &&
         (writer->staging_present || writer->final_present);
}

uint64_t actql_native_filesystem_writer_device(
  actql_native_filesystem_writer *writer
) {
  return writer == NULL ? 0 : writer->device;
}

uint64_t actql_native_filesystem_writer_inode(
  actql_native_filesystem_writer *writer
) {
  return writer == NULL ? 0 : writer->inode;
}

int32_t actql_native_filesystem_verify_generation(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length,
  uint64_t device,
  uint64_t inode,
  int64_t size
) {
  char *name_text = actql_copy_text(name, length);
  if (name_text == NULL) return 0;
  if (!actql_valid_file_component(name_text, (size_t)length)) {
    free(name_text);
    return 0;
  }
  struct stat status;
  bool matches = actql_stat_regular_at(root, name_text, &status) &&
                 actql_exact_generation(&status, device, inode, size);
  free(name_text);
  return matches;
}

int32_t actql_native_filesystem_inspect_generation(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length
) {
  if (root == NULL || root->fd < 0) return -1;
  actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, NULL);
  root->result_device = 0;
  root->result_inode = 0;
  root->result_size = 0;
  char *name_text = actql_copy_text(name, length);
  if (name_text == NULL) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "object name allocation failed");
    return -1;
  }
  if (!actql_valid_file_component(name_text, (size_t)length)) {
    free(name_text);
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "invalid object name");
    return 2;
  }
  struct stat status;
  if (fstatat(root->fd, name_text, &status, AT_SYMLINK_NOFOLLOW) != 0) {
    int stat_error = errno;
    free(name_text);
    if (stat_error == ENOENT) return 1;
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "inspect object generation", stat_error);
    return -1;
  }
  free(name_text);
  if (!S_ISREG(status.st_mode) || status.st_size < 0) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "object is not a regular generation");
    return 2;
  }
  root->result_device = (uint64_t)status.st_dev;
  root->result_inode = (uint64_t)status.st_ino;
  root->result_size = (int64_t)status.st_size;
  return 0;
}

uint64_t actql_native_filesystem_root_result_device(
  actql_native_filesystem_root *root
) {
  return root == NULL ? 0 : root->result_device;
}

uint64_t actql_native_filesystem_root_result_inode(
  actql_native_filesystem_root *root
) {
  return root == NULL ? 0 : root->result_inode;
}

int64_t actql_native_filesystem_root_result_size(
  actql_native_filesystem_root *root
) {
  return root == NULL ? 0 : root->result_size;
}

int32_t actql_native_filesystem_reclaim_generation(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length,
  uint64_t device,
  uint64_t inode,
  int64_t size
) {
  if (root == NULL || root->fd < 0) return -1;
  actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, NULL);
  char *name_text = actql_copy_text(name, length);
  if (name_text == NULL) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "object name allocation failed");
    return -1;
  }
  if (!actql_valid_name(name_text, (size_t)length) || size < 0) {
    free(name_text);
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "invalid object generation");
    return 1;
  }
  struct stat status;
  if (fstatat(root->fd, name_text, &status, AT_SYMLINK_NOFOLLOW) != 0) {
    int stat_error = errno;
    free(name_text);
    if (stat_error == ENOENT) {
      if (actql_sync_root(root) == 0) return 0;
      actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "sync Store root", errno);
      return -1;
    }
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling,
      "inspect committed file for reclamation",
      stat_error
    );
    return -1;
  }
  if (!S_ISREG(status.st_mode) ||
      !actql_exact_generation(&status, device, inode, size)) {
    free(name_text);
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "generation mismatch");
    return 1;
  }
  if (unlinkat(root->fd, name_text, 0) != 0) {
    int unlink_error = errno;
    free(name_text);
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling,
      "remove committed generation",
      unlink_error
    );
    return -1;
  }
  free(name_text);
  if (actql_sync_root(root) != 0) {
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "sync Store root", errno);
    return -1;
  }
  return 0;
}

int32_t actql_native_filesystem_sync_root(
  actql_native_filesystem_root *root
) {
  if (root == NULL || root->fd < 0) return -1;
  actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, NULL);
  if (actql_sync_root(root) == 0) return 0;
  actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "sync Store root", errno);
  return -1;
}

void actql_native_filesystem_test_fail_root_sync(
  actql_native_filesystem_root *root,
  int32_t failures
) {
  if (root == NULL) return;
  root->test_sync_failures = failures < 0 ? 0 : failures;
}

void actql_native_filesystem_test_fail_created_directory_inspect(
  actql_native_filesystem_root *root,
  int32_t failures
) {
  if (root != NULL) root->test_directory_inspect_failures = failures;
}

// 0: no acquisition; 1: acquired but identity unconfirmed; 2: exact identity.
int32_t actql_native_filesystem_root_result_directory_acquired(
  actql_native_filesystem_root *root
) {
  return root == NULL ? 0 : root->result_directory_acquired;
}

static int32_t actql_native_filesystem_reader_close_once(
  actql_native_filesystem_reader *reader
);

void *actql_native_filesystem_open_reader(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length,
  uint64_t device,
  uint64_t inode,
  int64_t size
) {
  actql_native_filesystem_reader *reader = moonbit_make_external_object(
    actql_native_filesystem_reader_finalize,
    sizeof(actql_native_filesystem_reader)
  );
  memset(reader, 0, sizeof(*reader));
  reader->fd = -1;
  reader->diagnostic_ceiling = root == NULL ? 0 : root->diagnostic_ceiling;
  reader->open_failure_kind = ACTQL_READER_OPEN_READ_FAILURE;
  reader->root = root;
  if (root != NULL) moonbit_incref(root);
  reader->device = device;
  reader->inode = inode;
  reader->size = size;
  if (root == NULL || root->fd < 0) {
    actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, "Store root is unavailable");
    return reader;
  }
  char *name_text = actql_copy_text(name, length);
  if (name_text == NULL) {
    actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, "object name allocation failed");
    return reader;
  }
  if (!actql_valid_file_component(name_text, (size_t)length) || size < 0) {
    free(name_text);
    actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, "invalid object generation");
    return reader;
  }
  reader->fd = openat(root->fd, name_text, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  int open_error = errno;
  free(name_text);
  if (reader->fd < 0) {
    actql_replace_bounded_errno_error(&reader->error, reader->diagnostic_ceiling, "open committed file", open_error);
    return reader;
  }
  struct stat status;
  if (fstat(reader->fd, &status) != 0) {
    int stat_error = errno;
    actql_native_filesystem_reader_close_once(reader);
    actql_replace_bounded_errno_error(&reader->error, reader->diagnostic_ceiling, "inspect committed file", stat_error);
    return reader;
  }
  if (!S_ISREG(status.st_mode) ||
      !actql_exact_generation(&status, device, inode, size)) {
    reader->open_failure_kind = ACTQL_READER_OPEN_GENERATION_MISMATCH;
    actql_native_filesystem_reader_close_once(reader);
    actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, "generation mismatch");
    return reader;
  }
  reader->ready = true;
  reader->open_failure_kind = 0;
  return reader;
}

int32_t actql_native_filesystem_reader_ready(
  actql_native_filesystem_reader *reader
) {
  return reader != NULL && reader->ready && reader->fd >= 0;
}

// Original physical open disposition, independent of fallible diagnostic text.
int32_t actql_native_filesystem_reader_open_failure_kind(
  actql_native_filesystem_reader *reader
) {
  return reader == NULL ? ACTQL_READER_OPEN_READ_FAILURE : reader->open_failure_kind;
}

moonbit_bytes_t actql_native_filesystem_reader_error(
  actql_native_filesystem_reader *reader
) {
  return actql_copy_diagnostic(reader == NULL ? "invalid reader" :
    reader->close_result < 0 ? reader->close_error : reader->error,
    reader == NULL ? 0 : reader->diagnostic_ceiling);
}

// Opening refusal and its cleanup outcome are separate original facts.
moonbit_bytes_t actql_native_filesystem_reader_open_error(
  actql_native_filesystem_reader *reader
) {
  return actql_copy_diagnostic(reader == NULL ? "invalid reader" : reader->error,
    reader == NULL ? 0 : reader->diagnostic_ceiling);
}

int32_t actql_native_filesystem_reader_next(
  actql_native_filesystem_reader *reader,
  int32_t max_bytes
) {
  if (reader == NULL || !reader->ready || reader->fd < 0 ||
      reader->finished) {
    return 2;
  }
  if (max_bytes <= 0 || max_bytes > 1048576) {
    actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, "invalid read size");
    return -1;
  }
  actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, NULL);
  free(reader->chunk);
  reader->chunk = NULL;
  reader->chunk_length = 0;
  reader->eof = false;
  unsigned char *chunk = malloc((size_t)max_bytes);
  if (chunk == NULL) {
    actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, "read buffer allocation failed");
    return -1;
  }
  ssize_t count;
  do {
    count = read(reader->fd, chunk, (size_t)max_bytes);
  } while (count < 0 && errno == EINTR);
  if (count < 0) {
    int read_error = errno;
    free(chunk);
    actql_replace_bounded_errno_error(&reader->error, reader->diagnostic_ceiling, "read committed file", read_error);
    return -1;
  }
  if (count == 0) {
    free(chunk);
    reader->eof = true;
    return 0;
  }
  if (reader->offset > reader->size ||
      count > reader->size - reader->offset) {
    free(chunk);
    actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, "generation mismatch");
    return 1;
  }
  reader->chunk = chunk;
  reader->chunk_length = (int32_t)count;
  reader->offset += (int64_t)count;
  return 0;
}

moonbit_bytes_t actql_native_filesystem_reader_chunk(
  actql_native_filesystem_reader *reader
) {
  int32_t length = reader == NULL ? 0 : reader->chunk_length;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw(length);
  if (length > 0) memcpy(bytes, reader->chunk, (size_t)length);
  return bytes;
}

int32_t actql_native_filesystem_reader_eof(
  actql_native_filesystem_reader *reader
) {
  return reader != NULL && reader->eof;
}

static int32_t actql_native_filesystem_reader_close_once(
  actql_native_filesystem_reader *reader
) {
  if (reader->close_result != 0) {
    return reader->close_result == 1 ? 0 : -1;
  }
  if (reader->fd < 0) return 0;
  actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, NULL);
  int descriptor = reader->fd;
  // Consume before close: on Linux and Darwin a reported error may follow FD
  // retirement/reuse. Retrying the integer could close a different file.
  reader->fd = -1;
  reader->close_result = -1;
  if (close(descriptor) != 0) {
    actql_replace_bounded_errno_error(&reader->close_error, reader->diagnostic_ceiling, "close reader", errno);
    return -1;
  }
  reader->close_result = 1;
  return 0;
}

int32_t actql_native_filesystem_reader_finish(
  actql_native_filesystem_reader *reader
) {
  if (reader == NULL || !reader->ready) return 3;
  if (reader->close_result < 0) return -1;
  if (reader->finished) return 0;
  if (reader->fd < 0) return 3;
  actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, NULL);
  if (reader->offset != reader->size) return 2;
  struct stat status;
  if (fstat(reader->fd, &status) != 0) {
    actql_replace_bounded_errno_error(&reader->error, reader->diagnostic_ceiling, "recheck committed file", errno);
    return -1;
  }
  if (!S_ISREG(status.st_mode) || !actql_exact_generation(
        &status,
        reader->device,
        reader->inode,
        reader->size
      )) {
    actql_replace_bounded_error(&reader->error, reader->diagnostic_ceiling, "generation mismatch");
    return 1;
  }
  if (actql_native_filesystem_reader_close_once(reader) != 0) return -1;
  reader->finished = true;
  return 0;
}

int32_t actql_native_filesystem_reader_close(
  actql_native_filesystem_reader *reader
) {
  if (reader == NULL) return 0;
  return actql_native_filesystem_reader_close_once(reader);
}

// Whitebox loss after a real close, not an observed kernel failure. The same
// Reader retains its sticky uncertainty; no retry closes a reused descriptor.
int32_t actql_native_filesystem_test_reader_consumed_unknown(
  actql_native_filesystem_reader *reader
) {
  if (reader == NULL || reader->fd < 0 ||
      actql_native_filesystem_reader_close_once(reader) != 0) return 0;
  reader->close_result = -1;
  actql_replace_bounded_error(&reader->close_error, reader->diagnostic_ceiling,
    "reader retirement observation unavailable");
  return 1;
}

// Creates one directory exclusively below the root and reports its identity.
// 0 with the identity in the root's result fields, 1 when the name exists,
// -1 otherwise.
int32_t actql_native_filesystem_create_directory(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length
) {
  if (root == NULL) return -1;
  root->result_directory_acquired = 0;
  if (root->fd < 0) return -1;
  actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, NULL);
  root->result_device = 0;
  root->result_inode = 0;
  root->result_size = 0;
  char *name_text = actql_copy_text(name, length);
  if (name_text == NULL) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "directory name allocation failed");
    return -1;
  }
  if (!actql_valid_name(name_text, (size_t)length)) {
    free(name_text);
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "invalid directory name");
    return -1;
  }
  if (mkdirat(root->fd, name_text, 0700) != 0) {
    int create_error = errno;
    free(name_text);
    if (create_error == EEXIST) return 1;
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "create directory", create_error);
    return -1;
  }
  root->result_directory_acquired = 1;
  struct stat status;
  int inspect_result;
  if (root->test_directory_inspect_failures > 0) {
    root->test_directory_inspect_failures--;
    errno = EIO;
    inspect_result = -1;
  } else {
    inspect_result = fstatat(root->fd, name_text, &status, AT_SYMLINK_NOFOLLOW);
  }
  if (inspect_result != 0 ||
      !S_ISDIR(status.st_mode)) {
    int stat_error = errno;
    free(name_text);
    // No identity: retain the allocation for reconciliation, never unlink
    // whichever entry happens to be at this name now.
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "inspect created directory", stat_error);
    return -1;
  }
  free(name_text);
  // Creation acquired this exact directory even if durability confirmation
  // fails next. Keep its identity available to the Store's cleanup owner.
  root->result_device = (uint64_t)status.st_dev;
  root->result_inode = (uint64_t)status.st_ino;
  root->result_directory_acquired = 2;
  if (actql_sync_root(root) != 0) {
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "sync Store root", errno);
    return -1;
  }
  return 0;
}

// Reports the identity of a directory below the root: 0 with the identity,
// 1 when absent, 2 when the name is not a directory, -1 otherwise.
int32_t actql_native_filesystem_inspect_directory(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length
) {
  if (root == NULL || root->fd < 0) return -1;
  actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, NULL);
  root->result_device = 0;
  root->result_inode = 0;
  root->result_size = 0;
  char *name_text = actql_copy_text(name, length);
  if (name_text == NULL) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "directory name allocation failed");
    return -1;
  }
  if (!actql_valid_name(name_text, (size_t)length)) {
    free(name_text);
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "invalid directory name");
    return 2;
  }
  struct stat status;
  if (fstatat(root->fd, name_text, &status, AT_SYMLINK_NOFOLLOW) != 0) {
    int stat_error = errno;
    free(name_text);
    if (stat_error == ENOENT) return 1;
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "inspect directory", stat_error);
    return -1;
  }
  free(name_text);
  if (!S_ISDIR(status.st_mode)) return 2;
  root->result_device = (uint64_t)status.st_dev;
  root->result_inode = (uint64_t)status.st_ino;
  return 0;
}

// Removes one exact empty directory below the root: 0 when removed or
// already absent, 1 when another directory or a file holds the name, 3 when
// it is not empty, -1 otherwise.
int32_t actql_native_filesystem_remove_directory(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length,
  uint64_t device,
  uint64_t inode
) {
  if (root == NULL || root->fd < 0) return -1;
  actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, NULL);
  char *name_text = actql_copy_text(name, length);
  if (name_text == NULL) {
    actql_replace_bounded_error(&root->error, root->diagnostic_ceiling, "directory name allocation failed");
    return -1;
  }
  if (!actql_valid_name(name_text, (size_t)length)) {
    free(name_text);
    return 1;
  }
  struct stat status;
  if (fstatat(root->fd, name_text, &status, AT_SYMLINK_NOFOLLOW) != 0) {
    int stat_error = errno;
    free(name_text);
    if (stat_error == ENOENT) {
      if (actql_sync_root(root) == 0) return 0;
      actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "sync Store root", errno);
      return -1;
    }
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "inspect directory for removal", stat_error);
    return -1;
  }
  if (!S_ISDIR(status.st_mode) || (uint64_t)status.st_dev != device ||
      (uint64_t)status.st_ino != inode) {
    free(name_text);
    return 1;
  }
  if (unlinkat(root->fd, name_text, AT_REMOVEDIR) != 0) {
    int remove_error = errno;
    free(name_text);
    if (remove_error == ENOTEMPTY || remove_error == EEXIST) return 3;
    if (remove_error == ENOENT) return 0;
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "remove directory", remove_error);
    return -1;
  }
  free(name_text);
  if (actql_sync_root(root) != 0) {
    actql_replace_bounded_errno_error(&root->error, root->diagnostic_ceiling, "sync Store root", errno);
    return -1;
  }
  return 0;
}

// Opens one directory below the root as a root of its own.
void *actql_native_filesystem_open_child_root(
  actql_native_filesystem_root *root,
  moonbit_bytes_t name,
  int32_t length
) {
  actql_native_filesystem_root *child = moonbit_make_external_object(
    actql_native_filesystem_root_finalize,
    sizeof(actql_native_filesystem_root)
  );
  memset(child, 0, sizeof(*child));
  child->fd = -1;
  // Like the absolute Root constructor, no descriptor exists until openat
  // succeeds. This is not inferred after a close attempt or lost response.
  child->close_result = 1;
  child->diagnostic_ceiling = root == NULL ? 0 : root->diagnostic_ceiling;
  if (root == NULL || root->fd < 0) {
    actql_replace_bounded_error(&child->error, child->diagnostic_ceiling, "Store root is unavailable");
    return child;
  }
  char *name_text = actql_copy_text(name, length);
  if (name_text == NULL) {
    actql_replace_bounded_error(&child->error, child->diagnostic_ceiling, "directory name allocation failed");
    return child;
  }
  if (!actql_valid_name(name_text, (size_t)length)) {
    free(name_text);
    actql_replace_bounded_error(&child->error, child->diagnostic_ceiling, "invalid directory name");
    return child;
  }
  child->fd = openat(
    root->fd,
    name_text,
    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
  );
  int open_error = errno;
  if (child->fd >= 0) child->close_result = 0;
  if (root->custody_path != NULL &&
      strlen(root->custody_path) + (size_t)length + 1 <= 4096) {
    size_t size = strlen(root->custody_path) + (size_t)length + 2;
    child->custody_path = malloc(size);
    if (child->custody_path != NULL) {
      snprintf(child->custody_path, size, "%s/%s", root->custody_path, name_text);
    }
  }
  free(name_text);
  if (child->fd < 0) {
    actql_replace_bounded_errno_error(&child->error, child->diagnostic_ceiling, "open allocation directory", open_error);
  }
  return child;
}

#ifdef ACTQL_SCOPED_READ_ALLOCATOR
#include "filesystem_read_context.inc"
#endif

/* This entrance borrows only the existing Domain's active current context.
 * Stock/unselected callers refuse before any Root allocation or descriptor
 * access. The status and original Root output are separate physical facts;
 * a failed constructor output remains original cleanup custody. */
MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_scoped_open_current_root(
  moonbit_bytes_t path, int32_t length, int32_t diagnostic_ceiling,
  actql_native_filesystem_root **output
) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (output == NULL || *output != NULL || diagnostic_ceiling <= 0)
    return ACTQL_OWNED_INVALID;
  actql_read_context *context = actql_bootstrap_current_read_context();
  if (context == NULL) return ACTQL_OWNED_INVALID;
  return actql_native_filesystem_scoped_open_root(
    context, path, length, diagnostic_ceiling, output);
#else
  (void)path;
  (void)length;
  (void)diagnostic_ceiling;
  (void)output;
  return -1; /* ACTQL_OWNED_INVALID; no active scoped provider was selected. */
#endif
}

/* Same current original, with the existing private Root constructor's complete
 * namespace/owner/mode/ACL checks. No generic Root or stock allocation fallback
 * is admitted when the current original read context is unavailable. */
MOONBIT_FFI_EXPORT int32_t actql_native_filesystem_scoped_open_current_private_root(
  moonbit_bytes_t path, int32_t length, int32_t diagnostic_ceiling,
  actql_native_filesystem_root **output
) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (output == NULL || *output != NULL || diagnostic_ceiling <= 0)
    return ACTQL_OWNED_INVALID;
  actql_read_context *context = actql_bootstrap_current_read_context();
  if (context == NULL) return ACTQL_OWNED_INVALID;
  return actql_native_filesystem_scoped_open_private_root(
    context, path, length, diagnostic_ceiling, output);
#else
  (void)path;
  (void)length;
  (void)diagnostic_ceiling;
  (void)output;
  return -1;
#endif
}

#include "filesystem_scoped_acquisition.inc"

#include "observed_component_member.inc"

// Readonly implementation facts before acquisition. No descriptor, allocation,
// authority or cleanup acknowledgement is issued here. The pinned runtime's
// external object adds its header and a trailing finalizer pointer; path,
// diagnostic and chunk allocations are separate from these payloads.
int64_t actql_native_filesystem_read_layout_field(int32_t field) {
  switch (field) {
    case 0: return (int64_t)sizeof(actql_native_filesystem_root);
    case 1: return (int64_t)sizeof(actql_native_filesystem_reader);
    case 2: return (int64_t)(sizeof(struct moonbit_object) +
      sizeof(void (*)(void *)));
    case 3: return (int64_t)sizeof(actql_native_observed_file_stat);
    case 4: return (int64_t)sizeof(actql_filesystem_scoped_acquisition);
    default: return -1;
  }
}

// The Writer shares the existing Root and keeps its own original descriptor,
// names and failed-close custody. Publish only its compiled payload/header;
// referenced names, diagnostics and Source/Store buffers remain separate.
int64_t actql_native_filesystem_write_layout_field(int32_t field) {
  switch (field) {
    case 0: return (int64_t)sizeof(actql_native_filesystem_writer);
    case 1: return (int64_t)(sizeof(struct moonbit_object) +
      sizeof(void (*)(void *)));
    default: return -1;
  }
}
