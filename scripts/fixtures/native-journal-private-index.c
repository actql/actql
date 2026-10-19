#define _DARWIN_C_SOURCE
#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L
#include "moonbit.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/attr.h>
#include <sys/mount.h>
#endif

_Noreturn void moonbit_panic(void) { abort(); }

static int fail_stat;
static int fail_close;
static int observed_descriptor = -1;
static int close_count;
static int stat_fault_count;
#ifdef __APPLE__
static int path_fault;
static int path_observations;
static int controlled_path_attributes(int fd, struct attrlist *attributes,
    void *buffer, size_t bytes, unsigned long options) {
  path_observations++;
  assert(attributes->commonattr == ATTR_CMN_FULLPATH);
  assert(bytes == sizeof(uint32_t) + sizeof(attrreference_t) + PATH_MAX);
  if (path_fault == 1) {errno = ENOTSUP; return -1;}
  int result = fgetattrlist(fd, attributes, buffer, bytes, options);
  if (result == 0 && path_fault == 2) {
    uint32_t truncated = (uint32_t)bytes + 1;
    memcpy(buffer, &truncated, sizeof(truncated));
  }
  return result;
}
#define fgetattrlist(...) controlled_path_attributes(__VA_ARGS__)
#endif
static int controlled_fstat(int fd, struct stat *info) {
  if (fail_stat) {
    fail_stat--;
    stat_fault_count++;
    observed_descriptor = fd;
    errno = EINTR;
    return -1;
  }
  return fstat(fd, info);
}
static int controlled_close(int fd) {
  close_count++;
  observed_descriptor = fd;
  int result = close(fd);
  if (fail_close) {
    fail_close = 0;
    assert(result == 0);
    errno = EIO;
    return -1;
  }
  return result;
}
#define fstat controlled_fstat
#define close controlled_close
#include "../../src/platform_native/remote_journal/inspection_stub.c"
#undef close
#undef fstat
#ifdef __APPLE__
#undef fgetattrlist
#endif

int main(int argc, char **argv) {
  assert(argc == 3);
  assert(mkdir(argv[2], 0700) == 0);
  char *source = inspection_suffix(argv[2], "/source.sqlite3");
  int fd = open(source, O_WRONLY | O_CREAT | O_EXCL, 0600);
  assert(fd >= 0 && write(fd, "original", 8) == 8 && close(fd) == 0);
  moonbit_bytes_t path = moonbit_make_bytes_raw((int32_t)strlen(source));
  memcpy(path, source, strlen(source));
  if (strcmp(argv[1], "selected-source-oversized") == 0 ||
      strcmp(argv[1], "selected-source-boundary") == 0) {
    int length = strcmp(argv[1], "selected-source-boundary") == 0 ? 4096 : 4097;
    moonbit_bytes_t oversized = moonbit_make_bytes_raw(length);
    memset(oversized, 'x', (size_t)length);
    actql_journal_inspection *refused = inspection_open_bounded_original(
      oversized, length, 1024, getenv("TMPDIR"), 1);
    assert(!refused->ready && refused->directory == NULL &&
      refused->descriptors[0] == -1 && refused->descriptors[1] == -1 &&
      refused->path_descriptor == -1 && refused->output_descriptor == -1);
    if (length == 4097) {
      assert(refused->source == NULL && refused->wal == NULL &&
        refused->journal == NULL);
      assert(strstr(refused->error, "original command inspection path unavailable"));
    } else {
      /* The exact boundary reaches ordinary physical path validation. It is
       * not truncated or reclassified as absent/admitted when the OS refuses. */
      assert(refused->source && refused->wal && refused->journal);
      assert(strstr(refused->error, "original command inspection path unavailable") == NULL);
      assert(!refused->absent);
    }
    assert(inspection_close(refused));
    moonbit_decref(refused);
    moonbit_decref(oversized);
    goto finish;
  }
  if (strcmp(argv[1], "command-original-unavailable") == 0 ||
      strcmp(argv[1], "selected-scratch-oversized") == 0) {
    char oversized[4098];
    memset(oversized, 'x', sizeof(oversized) - 1);
    oversized[sizeof(oversized) - 1] = 0;
    actql_journal_inspection *refused =
      strcmp(argv[1], "command-original-unavailable") == 0
      ? actql_journal_inspection_open_command_bounded(
          path, (int32_t)strlen(source), 1024)
      : inspection_open_bounded_original(
          path, (int32_t)strlen(source), 1024, oversized, 1);
    assert(!refused->ready && refused->source == NULL &&
      refused->directory == NULL && refused->copy == NULL);
    assert(refused->descriptors[0] == -1 && refused->descriptors[1] == -1 &&
      refused->output_descriptor == -1);
    assert(strstr(refused->error, "original command inspection scratch unavailable"));
    assert(inspection_close(refused));
    moonbit_decref(refused);
    goto finish;
  }
  if (strcmp(argv[1], "selected-scratch-original") == 0 ||
      strncmp(argv[1], "selected-path-", 14) == 0) {
    /* Exercise the selected copy implementation with an explicit original
     * input. This is not an admitted bootstrap or an ordinary command. */
    char *original_scratch = strdup(strcmp(argv[1], "selected-path-overlap") == 0
      ? argv[2] : getenv("TMPDIR"));
    assert(original_scratch != NULL);
    assert(setenv("TMPDIR", "/not-the-original-command-scratch", 1) == 0);
#ifdef __APPLE__
    path_fault = strcmp(argv[1], "selected-path-unsupported") == 0 ? 1 :
      strcmp(argv[1], "selected-path-truncated") == 0 ? 2 : 0;
    fail_close = strcmp(argv[1], "selected-path-close-unknown") == 0;
#endif
    actql_journal_inspection *selected = inspection_open_bounded_original(
      path, (int32_t)strlen(source), 1024, original_scratch, 1);
#ifdef __APPLE__
    if (path_fault || strcmp(argv[1], "selected-path-overlap") == 0) {
      assert(!selected->ready && selected->directory == NULL &&
        selected->path_descriptor == -1 && !selected->path_close_errno);
      assert(path_observations == 2 && inspection_close(selected));
      moonbit_decref(selected);
    } else if (strcmp(argv[1], "selected-path-close-unknown") == 0) {
      assert(!selected->ready && selected->directory == NULL &&
        selected->path_descriptor >= 0 && selected->path_close_errno == EIO &&
        path_observations == 1);
      int reused = open("/dev/null", O_RDONLY);
      assert(reused == selected->path_descriptor);
      int before = close_count;
      assert(!inspection_close(selected) && !inspection_close(selected));
      assert(close_count == before && fcntl(reused, F_GETFD) >= 0);
      assert(fcntl(selected->descriptors[0], F_GETFD) >= 0);
      assert(close(reused) == 0);
      /* Keep this receiver and its source FD unacknowledged. Process exit is
       * not path/source retirement, and the consumed path FD is not retried. */
    } else {
    assert(selected->ready && !selected->absent);
    assert(strncmp(selected->directory, original_scratch,
      strlen(original_scratch)) == 0);
    assert(actql_journal_inspection_prepare_private_index(selected));
    assert(actql_journal_inspection_validate(selected));
    assert(inspection_close(selected));
    moonbit_decref(selected);
    }
#else
    assert(!selected->ready && inspection_close(selected));
    moonbit_decref(selected);
#endif
    assert(setenv("TMPDIR", original_scratch, 1) == 0);
    free(original_scratch);
    goto finish;
  }
  int output_unknown = strcmp(argv[1], "output-close-unknown") == 0;
  fail_close = output_unknown;
  actql_journal_inspection *owner = inspection_open_bounded(
    path, (int32_t)strlen(source), 1024);
  char *index = NULL;
  if (output_unknown) {
    assert(!owner->ready && owner->output_descriptor >= 0);
    int original = observed_descriptor;
    int held_source = owner->descriptors[0];
    assert(held_source >= 0 && fcntl(held_source, F_GETFD) >= 0);
    int reused = open("/dev/null", O_RDONLY);
    assert(reused == original);
    int before = close_count;
    char primary[sizeof(owner->error)];
    memcpy(primary, owner->error, sizeof(primary));
    assert(!inspection_close(owner) && !inspection_close(owner));
    assert(close_count == before && fcntl(reused, F_GETFD) >= 0);
    assert(fcntl(held_source, F_GETFD) >= 0);
    assert(memcmp(primary, owner->error, sizeof(primary)) == 0);
    assert(access(owner->copy, F_OK) == 0);
    assert(close(reused) == 0);
    goto done;
  }
  assert(owner->ready && !owner->absent);
  index = inspection_suffix(owner->copy, "-shm");
  int before = close_count;
  if (strcmp(argv[1], "source-close-unknown") == 0) {
    int original = owner->descriptors[0];
    fail_close = 1;
    assert(!inspection_close(owner));
    assert(observed_descriptor == original && close_count == before + 1);
    int reused = open("/dev/null", O_RDONLY);
    assert(reused == original);
    char primary[sizeof(owner->error)];
    memcpy(primary, owner->error, sizeof(primary));
    assert(!inspection_close(owner) && !inspection_close(owner));
    assert(close_count == before + 1 && fcntl(reused, F_GETFD) >= 0);
    assert(memcmp(primary, owner->error, sizeof(primary)) == 0);
    assert(access(owner->copy, F_OK) == 0);
    assert(close(reused) == 0);
  } else if (strcmp(argv[1], "generic") == 0) {
    assert(access(index, F_OK) == -1 && errno == ENOENT);
    assert(inspection_close(owner));
  } else {
    if (strcmp(argv[1], "collision") == 0) {
      fd = open(index, O_WRONLY | O_CREAT | O_EXCL, 0600);
      assert(fd >= 0 && write(fd, "foreign", 7) == 7 && close(fd) == 0);
    }
    fail_stat = strcmp(argv[1], "stat-failure") == 0 ||
      strcmp(argv[1], "unobserved-identity-replacement") == 0;
    if (strcmp(argv[1], "stat-unavailable") == 0) fail_stat = 2;
    fail_close = strcmp(argv[1], "close-unknown") == 0;
    int ready = actql_journal_inspection_prepare_private_index(owner);
    assert(close_count == before + (strcmp(argv[1], "collision") != 0));
    assert(!actql_journal_inspection_prepare_private_index(owner));
    if (strcmp(argv[1], "collision") == 0) {
      assert(!ready && !owner->private_index_created);
      assert(!inspection_close(owner));
      struct stat current;
      assert(lstat(index, &current) == 0 && current.st_size == 7);
    } else if (strcmp(argv[1], "close-unknown") == 0) {
      assert(!ready && owner->private_index_close_unknown);
      int original = observed_descriptor;
      int reused = open("/dev/null", O_RDONLY);
      assert(reused == original);
      assert(!inspection_close(owner) && !inspection_close(owner));
      assert(close_count == before + 1 && fcntl(reused, F_GETFD) >= 0);
      assert(access(index, F_OK) == 0);
      assert(close(reused) == 0);
    } else if (strcmp(argv[1], "unobserved-identity-replacement") == 0) {
      assert(!ready && stat_fault_count == 1);
      assert(owner->private_index_descriptor == -1);
      assert(owner->private_index_primary_errno == EINTR);
      char *held = inspection_suffix(index, ".held");
      assert(rename(index, held) == 0);
      fd = open(index, O_WRONLY | O_CREAT | O_EXCL, 0600);
      assert(fd >= 0 && write(fd, "foreign", 7) == 7 && close(fd) == 0);
      assert(!inspection_close(owner));
      struct stat current;
      assert(lstat(index, &current) == 0 && current.st_size == 7);
      assert(access(held, F_OK) == 0);
      free(held);
    } else if (strcmp(argv[1], "stat-failure") == 0) {
      assert(!ready && !owner->private_index_close_unknown);
      assert(owner->private_index_descriptor == -1);
      assert(owner->private_index_identity_observed);
      assert(owner->private_index_primary_errno == EINTR);
      assert(strstr(owner->error, "inspect private inspection index failed"));
      assert(inspection_close(owner) && inspection_close(owner));
      assert(access(index, F_OK) == -1 && errno == ENOENT);
    } else if (strcmp(argv[1], "stat-unavailable") == 0) {
      assert(!ready && stat_fault_count == 2);
      assert(!owner->private_index_identity_observed);
      assert(owner->private_index_primary_errno == EINTR);
      assert(owner->private_index_descriptor == -1);
      assert(!inspection_close(owner) && !inspection_close(owner));
      assert(access(index, F_OK) == 0);
    } else {
      assert(ready && actql_journal_inspection_private_index_ready(owner));
      if (strcmp(argv[1], "replacement") == 0) {
        char *held = inspection_suffix(index, ".held");
        assert(rename(index, held) == 0);
        fd = open(index, O_WRONLY | O_CREAT | O_EXCL, 0600);
        assert(fd >= 0 && write(fd, "foreign", 7) == 7 && close(fd) == 0);
        assert(!actql_journal_inspection_private_index_ready(owner));
        assert(!inspection_close(owner));
        struct stat current;
        assert(lstat(index, &current) == 0 && current.st_size == 7);
        free(held);
      } else {
        assert(inspection_close(owner) && inspection_close(owner));
        assert(access(index, F_OK) == -1 && errno == ENOENT);
      }
    }
  }
done:
  assert(access(source, F_OK) == 0);
  free(index);
finish:
  assert(access(source, F_OK) == 0);
  printf("{\"case\":\"%s\",\"passed\":true,\"sqliteExecuted\":false,"
         "\"kernelFaultObserved\":false}\n", argv[1]);
  free(source);
  moonbit_decref(path);
  return 0;
}
