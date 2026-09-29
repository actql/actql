#define _POSIX_C_SOURCE 200809L
#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#endif

#include "moonbit.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

// The executor slot lock is one file per Site executor slot. It is opened,
// never unlinked or recreated, and held with flock(2). A lock held through an
// open file description survives in every process that inherited that
// description, so ownership passes from parent to child without a gap.

enum {
  ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD = 10,
  ACTQL_EXECUTOR_SLOT_MAX_ARGUMENTS = 64,
};

static char *actql_executor_slot_text(moonbit_bytes_t bytes, int32_t length) {
  if (length <= 0 || memchr(bytes, 0, (size_t)length) != NULL) return NULL;
  char *text = malloc((size_t)length + 1);
  if (text == NULL) return NULL;
  memcpy(text, bytes, (size_t)length);
  text[length] = '\0';
  return text;
}

static bool actql_executor_slot_private(const struct stat *status) {
  return S_ISREG(status->st_mode) && status->st_uid == geteuid() &&
    (status->st_mode & 077) == 0;
}

// Opens the slot file, creating it once when absent. Returns a descriptor at
// or above ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD, close-on-exec, or -1.
int32_t actql_executor_slot_open(moonbit_bytes_t path, int32_t length) {
  char *text = actql_executor_slot_text(path, length);
  if (text == NULL) return -1;
  int descriptor = open(
    text,
    O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
    S_IRUSR | S_IWUSR
  );
  free(text);
  if (descriptor < 0) return -1;
  struct stat status;
  if (fstat(descriptor, &status) != 0 || !actql_executor_slot_private(&status)) {
    close(descriptor);
    return -1;
  }
  int moved = fcntl(
    descriptor,
    F_DUPFD_CLOEXEC,
    ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD
  );
  close(descriptor);
  return moved < 0 ? -1 : moved;
}

// 0 acquired (or already held through this description), 1 held elsewhere,
// -1 error.
int32_t actql_executor_slot_try_lock(int32_t descriptor) {
  if (descriptor < 0) return -1;
  while (true) {
    if (flock(descriptor, LOCK_EX | LOCK_NB) == 0) return 0;
    if (errno == EINTR) continue;
    return errno == EWOULDBLOCK ? 1 : -1;
  }
}

// Confirms that the descriptor is the current slot file named by path (not a
// replaced or recreated file) and that this description holds the lock.
// 0 held, 1 not held (another description holds it), 2 replaced, -1 error.
int32_t actql_executor_slot_verify(
  int32_t descriptor,
  moonbit_bytes_t path,
  int32_t length
) {
  char *text = actql_executor_slot_text(path, length);
  if (text == NULL || descriptor < 0) {
    free(text);
    return -1;
  }
  struct stat named;
  struct stat opened;
  bool named_valid = lstat(text, &named) == 0;
  free(text);
  if (fstat(descriptor, &opened) != 0 || !actql_executor_slot_private(&opened)) {
    return -1;
  }
  if (!named_valid || named.st_dev != opened.st_dev ||
      named.st_ino != opened.st_ino || !S_ISREG(named.st_mode)) {
    return 2;
  }
  int32_t locked = actql_executor_slot_try_lock(descriptor);
  return locked;
}

int32_t actql_executor_slot_close(int32_t descriptor) {
  if (descriptor < 0) return -1;
  return close(descriptor) == 0 ? 0 : -1;
}

// Starts executable with NUL-separated arguments (argv[0] included). The slot
// description is installed at target_descriptor in the child only, without
// close-on-exec, so the child and its descendants hold the same lock. Every
// other private descriptor stays close-on-exec. Returns the child pid or -1.
int32_t actql_executor_slot_spawn(
  moonbit_bytes_t executable,
  int32_t executable_length,
  moonbit_bytes_t arguments,
  int32_t arguments_length,
  int32_t descriptor,
  int32_t target_descriptor
) {
  if (descriptor < ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD ||
      target_descriptor < 3 ||
      target_descriptor >= ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD ||
      arguments_length <= 0 || arguments[arguments_length - 1] != 0) {
    return -1;
  }
  char *path = actql_executor_slot_text(executable, executable_length);
  if (path == NULL) return -1;
  char *block = malloc((size_t)arguments_length);
  if (block == NULL) {
    free(path);
    return -1;
  }
  memcpy(block, arguments, (size_t)arguments_length);
  char *argv[ACTQL_EXECUTOR_SLOT_MAX_ARGUMENTS + 1];
  int count = 0;
  int32_t offset = 0;
  bool valid = true;
  while (offset < arguments_length) {
    if (count == ACTQL_EXECUTOR_SLOT_MAX_ARGUMENTS) {
      valid = false;
      break;
    }
    argv[count] = block + offset;
    count += 1;
    offset += (int32_t)strlen(block + offset) + 1;
  }
  argv[count] = NULL;
  if (!valid || count == 0) {
    free(block);
    free(path);
    return -1;
  }
  posix_spawn_file_actions_t actions;
  if (posix_spawn_file_actions_init(&actions) != 0) {
    free(block);
    free(path);
    return -1;
  }
  // dup2 onto a different number clears close-on-exec on the target only.
  bool configured =
    posix_spawn_file_actions_adddup2(&actions, descriptor, target_descriptor) ==
    0;
  pid_t pid = -1;
  int spawned = configured
    ? posix_spawn(&pid, path, &actions, NULL, argv, environ)
    : -1;
  posix_spawn_file_actions_destroy(&actions);
  free(block);
  free(path);
  return spawned == 0 && pid > 0 ? (int32_t)pid : -1;
}

// -2 still running (non-blocking), exit status 0..255, 256 + signal when
// terminated by a signal, -1 error.
int32_t actql_executor_slot_wait(int32_t pid, int32_t block) {
  if (pid <= 0) return -1;
  int status = 0;
  while (true) {
    pid_t observed = waitpid((pid_t)pid, &status, block ? 0 : WNOHANG);
    if (observed == 0) return -2;
    if (observed < 0) {
      if (errno == EINTR) continue;
      return -1;
    }
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 256 + WTERMSIG(status);
    return -1;
  }
}

int32_t actql_executor_slot_signal(int32_t pid, int32_t signal_number) {
  if (pid <= 0) return -1;
  return kill((pid_t)pid, signal_number) == 0 ? 0 : -1;
}

moonbit_bytes_t actql_executor_slot_current_executable(void) {
  char output[PATH_MAX];
  size_t length = 0;
#if defined(__APPLE__)
  uint32_t size = PATH_MAX;
  if (_NSGetExecutablePath(output, &size) == 0) length = strlen(output);
#elif defined(__linux__)
  ssize_t count = readlink("/proc/self/exe", output, PATH_MAX - 1);
  if (count > 0 && count < PATH_MAX) length = (size_t)count;
#endif
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)length);
  if (length > 0) memcpy(bytes, output, length);
  return bytes;
}
