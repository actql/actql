#define _DARWIN_C_SOURCE
#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L
#include "moonbit.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

_Noreturn void moonbit_panic(void) { abort(); }

static int fail_stat;
static int fail_close;
static int observed_descriptor = -1;
static int close_count;
static int controlled_fstat(int fd, struct stat *info) {
  if (fail_stat) {
    fail_stat = 0;
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

int main(int argc, char **argv) {
  assert(argc == 3);
  assert(mkdir(argv[2], 0700) == 0);
  char *source = inspection_suffix(argv[2], "/source.sqlite3");
  int fd = open(source, O_WRONLY | O_CREAT | O_EXCL, 0600);
  assert(fd >= 0 && write(fd, "original", 8) == 8 && close(fd) == 0);
  moonbit_bytes_t path = moonbit_make_bytes_raw((int32_t)strlen(source));
  memcpy(path, source, strlen(source));
  actql_journal_inspection *owner = inspection_open_bounded(
    path, (int32_t)strlen(source), 1024);
  assert(owner->ready && !owner->absent);
  char *index = inspection_suffix(owner->copy, "-shm");
  int before = close_count;
  if (strcmp(argv[1], "generic") == 0) {
    assert(access(index, F_OK) == -1 && errno == ENOENT);
    assert(inspection_close(owner));
  } else {
    fail_stat = strcmp(argv[1], "stat-failure") == 0;
    fail_close = strcmp(argv[1], "close-unknown") == 0;
    int ready = actql_journal_inspection_prepare_private_index(owner);
    assert(close_count == before + 1);
    assert(!actql_journal_inspection_prepare_private_index(owner));
    if (strcmp(argv[1], "close-unknown") == 0) {
      assert(!ready && owner->private_index_close_unknown);
      int original = observed_descriptor;
      int reused = open("/dev/null", O_RDONLY);
      assert(reused == original);
      assert(!inspection_close(owner) && !inspection_close(owner));
      assert(close_count == before + 1 && fcntl(reused, F_GETFD) >= 0);
      assert(access(index, F_OK) == 0);
      assert(close(reused) == 0);
    } else if (strcmp(argv[1], "stat-failure") == 0) {
      assert(!ready && !owner->private_index_close_unknown);
      assert(owner->private_index_descriptor == -1);
      assert(strstr(owner->error, "inspect private inspection index failed"));
      assert(inspection_close(owner) && inspection_close(owner));
      assert(access(index, F_OK) == -1 && errno == ENOENT);
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
  assert(access(source, F_OK) == 0);
  printf("{\"case\":\"%s\",\"passed\":true,\"sqliteExecuted\":false,"
         "\"kernelFaultObserved\":false}\n", argv[1]);
  free(index);
  free(source);
  return 0;
}
