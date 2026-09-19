#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "moonbit.h"

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
  int fd;
  char *error;
} actql_native_filesystem_root;

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
} actql_native_filesystem_writer;

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

static bool actql_writer_name_matches(
  actql_native_filesystem_writer *writer,
  const char *name,
  bool final_name
) {
  const char *selected = final_name ? writer->final_name : writer->staging_name;
  return selected != NULL && strcmp(selected, name) == 0;
}

static int actql_close_writer_file(actql_native_filesystem_writer *writer) {
  if (writer->fd < 0) return 0;
  int descriptor = writer->fd;
  writer->fd = -1;
  if (close(descriptor) == 0) return 0;
  actql_replace_errno_error(&writer->error, "close writer", errno);
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
    actql_replace_errno_error(&writer->error, "inspect owned file", errno);
    return -1;
  }
  if (!S_ISREG(status.st_mode) || !actql_exact_generation(
        &status,
        writer->device,
        writer->inode,
        writer->written
      )) {
    actql_replace_error(&writer->error, "owned file generation changed");
    return 2;
  }
  if (unlinkat(writer->root->fd, name, 0) != 0) {
    actql_replace_errno_error(&writer->error, "remove owned file", errno);
    return -1;
  }
  *present = false;
  return 0;
}

static void actql_native_filesystem_root_finalize(void *value) {
  actql_native_filesystem_root *root = value;
  if (root->fd >= 0) {
    close(root->fd);
    root->fd = -1;
  }
  free(root->error);
  root->error = NULL;
}

static void actql_native_filesystem_writer_finalize(void *value) {
  actql_native_filesystem_writer *writer = value;
  if (writer->fd >= 0) {
    close(writer->fd);
    writer->fd = -1;
  }
  if (writer->root != NULL && writer->root->fd >= 0) {
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
  writer->staging_name = NULL;
  writer->final_name = NULL;
  writer->error = NULL;
  if (writer->root != NULL) {
    moonbit_decref(writer->root);
    writer->root = NULL;
  }
}

void *actql_native_filesystem_open_root(
  moonbit_bytes_t path,
  int32_t length
) {
  actql_native_filesystem_root *root = moonbit_make_external_object(
    actql_native_filesystem_root_finalize,
    sizeof(actql_native_filesystem_root)
  );
  memset(root, 0, sizeof(*root));
  root->fd = -1;
  char *path_text = actql_copy_text(path, length);
  if (path_text == NULL) {
    actql_replace_error(&root->error, "root path allocation failed");
    return root;
  }
  root->fd = open(path_text, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  int open_error = errno;
  free(path_text);
  if (root->fd < 0) {
    actql_replace_errno_error(&root->error, "open Store root", open_error);
  }
  return root;
}

int32_t actql_native_filesystem_root_ready(
  actql_native_filesystem_root *root
) {
  return root != NULL && root->fd >= 0;
}

moonbit_bytes_t actql_native_filesystem_root_error(
  actql_native_filesystem_root *root
) {
  return actql_copy_bytes(root == NULL ? "invalid Store root" : root->error);
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
    actql_replace_error(&writer->error, "Store root is unavailable");
    return writer;
  }
  if (writer->staging_name == NULL) {
    actql_replace_error(&writer->error, "staging name allocation failed");
    return writer;
  }
  if (!actql_valid_name(writer->staging_name, (size_t)length)) {
    actql_replace_error(&writer->error, "invalid staging name");
    return writer;
  }
  if (max_bytes < 0) {
    actql_replace_error(&writer->error, "negative writer limit");
    return writer;
  }
  writer->fd = openat(
    root->fd,
    writer->staging_name,
    O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW,
    0600
  );
  if (writer->fd < 0) {
    actql_replace_errno_error(&writer->error, "create staging file", errno);
    return writer;
  }
  struct stat status;
  if (fstat(writer->fd, &status) != 0) {
    int stat_error = errno;
    close(writer->fd);
    writer->fd = -1;
    unlinkat(root->fd, writer->staging_name, 0);
    actql_replace_errno_error(&writer->error, "inspect staging file", stat_error);
    return writer;
  }
  if (!S_ISREG(status.st_mode) || status.st_size != 0) {
    close(writer->fd);
    writer->fd = -1;
    unlinkat(root->fd, writer->staging_name, 0);
    actql_replace_error(&writer->error, "staging file is not empty and regular");
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

moonbit_bytes_t actql_native_filesystem_writer_error(
  actql_native_filesystem_writer *writer
) {
  return actql_copy_bytes(writer == NULL ? "invalid writer" : writer->error);
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
  actql_replace_error(&writer->error, NULL);
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
      actql_replace_errno_error(&writer->error, "write staging file", write_error);
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
  if (writer == NULL || !writer->ready || writer->cancelled ||
      writer->cleanup_requested) {
    return 3;
  }
  char *final_name = actql_copy_text(name, length);
  if (final_name == NULL) {
    actql_replace_error(&writer->error, "final name allocation failed");
    return -1;
  }
  if (!actql_valid_name(final_name, (size_t)length)) {
    free(final_name);
    actql_replace_error(&writer->error, "invalid final name");
    return -1;
  }
  if (writer->final_name == NULL) {
    writer->final_name = final_name;
  } else {
    bool matches = actql_writer_name_matches(writer, final_name, true);
    free(final_name);
    if (!matches) return 3;
  }
  actql_replace_error(&writer->error, NULL);
  if (writer->sealed) return 0;

  if (writer->fd >= 0) {
    if (fsync(writer->fd) != 0) {
      actql_replace_errno_error(&writer->error, "sync staging file", errno);
      return -1;
    }
    struct stat status;
    if (fstat(writer->fd, &status) != 0) {
      actql_replace_errno_error(&writer->error, "inspect staging writer", errno);
      return -1;
    }
    if (!S_ISREG(status.st_mode) || status.st_size < 0 ||
        (uint64_t)status.st_dev != writer->device ||
        (uint64_t)status.st_ino != writer->inode ||
        (int64_t)status.st_size != writer->written) {
      actql_replace_error(&writer->error, "staging writer generation changed");
      return 2;
    }
    if (actql_close_writer_file(writer) != 0) return -1;
  }

  if (!writer->final_present) {
    if (!writer->staging_present) {
      actql_replace_error(&writer->error, "staging file is unavailable");
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
      actql_replace_errno_error(&writer->error, "link committed file", errno);
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
    actql_replace_errno_error(&writer->error, "inspect committed file", errno);
    return -1;
  }
  if (!S_ISREG(final_status.st_mode) || !actql_exact_generation(
        &final_status,
        writer->device,
        writer->inode,
        writer->written
      )) {
    actql_replace_error(&writer->error, "committed file generation changed");
    return 2;
  }

  int remove_result = actql_remove_owned_name(
    writer,
    writer->staging_name,
    &writer->staging_present
  );
  if (remove_result != 0) return remove_result;
  if (fsync(writer->root->fd) != 0) {
    actql_replace_errno_error(&writer->error, "sync Store root", errno);
    return -1;
  }
  if (fstatat(
        writer->root->fd,
        writer->final_name,
        &final_status,
        AT_SYMLINK_NOFOLLOW
      ) != 0) {
    actql_replace_errno_error(&writer->error, "recheck committed file", errno);
    return -1;
  }
  if (!S_ISREG(final_status.st_mode) || !actql_exact_generation(
        &final_status,
        writer->device,
        writer->inode,
        writer->written
      )) {
    actql_replace_error(&writer->error, "committed generation was not retained");
    return 2;
  }
  writer->sealed = true;
  return 0;
}

int32_t actql_native_filesystem_writer_cancel(
  actql_native_filesystem_writer *writer
) {
  if (writer == NULL || !writer->ready) return 0;
  if (writer->cancelled) return 0;
  writer->cleanup_requested = true;
  writer->sealed = false;
  actql_replace_error(&writer->error, NULL);
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
  if (fsync(writer->root->fd) != 0) {
    actql_replace_errno_error(&writer->error, "sync Store root", errno);
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
  if (writer == NULL || !writer->ready || writer->cancelled) return 0;
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
  if (!actql_valid_name(name_text, (size_t)length)) {
    free(name_text);
    return 0;
  }
  struct stat status;
  bool matches = actql_stat_regular_at(root, name_text, &status) &&
                 actql_exact_generation(&status, device, inode, size);
  free(name_text);
  return matches;
}
