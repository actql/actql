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
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

// The executor slot lock is one file per Site executor slot. It is opened,
// never unlinked or recreated, and held with flock(2). A lock held through an
// open file description survives in every process that inherited that
// description, so ownership passes from parent to child without a gap.

enum {
  ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD = 10,
  ACTQL_EXECUTOR_SLOT_MAX_ARGUMENTS = 256,
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
  int32_t target_descriptor,
  int32_t input_descriptor
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
  // An optional pipe read end becomes the holder's standard input.
  if (configured && input_descriptor >= 0) {
    configured =
      posix_spawn_file_actions_adddup2(&actions, input_descriptor, 0) == 0;
  }
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

// Process control for a resident Site parent: a termination request is only
// recorded here; the resident loop decides what to stop.
static volatile sig_atomic_t actql_executor_slot_terminate_flag = 0;

static void actql_executor_slot_on_terminate(int signal_number) {
  (void)signal_number;
  actql_executor_slot_terminate_flag = 1;
}

int32_t actql_executor_slot_install_termination(void) {
  // A holder that ended closes its channel; a write to it must fail, not
  // stop the control process.
  signal(SIGPIPE, SIG_IGN);
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = actql_executor_slot_on_terminate;
  sigemptyset(&action.sa_mask);
  if (sigaction(SIGTERM, &action, NULL) != 0) return -1;
  if (sigaction(SIGINT, &action, NULL) != 0) return -1;
  return 0;
}

int32_t actql_executor_slot_termination_requested(void) {
  return actql_executor_slot_terminate_flag ? 1 : 0;
}

void actql_executor_slot_sleep_ms(int32_t milliseconds) {
  if (milliseconds <= 0) return;
  struct timespec remaining = {
    .tv_sec = milliseconds / 1000,
    .tv_nsec = (long)(milliseconds % 1000) * 1000000L,
  };
  // A termination request interrupts the wait.
  while (nanosleep(&remaining, &remaining) != 0 && errno == EINTR &&
         !actql_executor_slot_terminate_flag) {
  }
}

// Appends one line and syncs it before returning, for acceptance evidence
// that must be durable before the next step. 0 on success, -1 otherwise.
int32_t actql_executor_slot_append_line(
  moonbit_bytes_t path,
  int32_t path_length,
  moonbit_bytes_t line,
  int32_t line_length
) {
  char *text = actql_executor_slot_text(path, path_length);
  if (text == NULL || line_length < 0) {
    free(text);
    return -1;
  }
  int descriptor = open(
    text,
    O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
    S_IRUSR | S_IWUSR
  );
  free(text);
  if (descriptor < 0) return -1;
  bool written = true;
  int32_t offset = 0;
  while (written && offset < line_length) {
    ssize_t count = write(
      descriptor,
      line + offset,
      (size_t)(line_length - offset)
    );
    if (count < 0) {
      if (errno == EINTR) continue;
      written = false;
    } else {
      offset += (int32_t)count;
    }
  }
  if (written && write(descriptor, "\n", 1) != 1) written = false;
  if (written && fsync(descriptor) != 0) written = false;
  if (close(descriptor) != 0) written = false;
  return written ? 0 : -1;
}

// Writes one line, newline included by the caller, to standard output
// unbuffered, so progress reaches a pipe in order even when the process ends
// abnormally. A line within PIPE_BUF goes out in one atomic write, so another
// process writing to the same pipe cannot split it. 0 on success.
int32_t actql_executor_slot_write_stdout_line(
  moonbit_bytes_t line,
  int32_t line_length
) {
  int32_t offset = 0;
  while (offset < line_length) {
    ssize_t count = write(1, line + offset, (size_t)(line_length - offset));
    if (count < 0) {
      if (errno == EINTR) continue;
      return -1;
    }
    offset += (int32_t)count;
  }
  return 0;
}

// A one-way channel from the control process to a holder: returns
// (read_fd << 16) | write_fd, both close-on-exec and above the private
// range, or -1. The read end is installed as the holder's standard input.
int32_t actql_executor_slot_open_channel(void) {
  int ends[2];
  if (pipe(ends) != 0) return -1;
  int read_end = fcntl(ends[0], F_DUPFD_CLOEXEC,
    ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD);
  int write_end = fcntl(ends[1], F_DUPFD_CLOEXEC,
    ACTQL_EXECUTOR_SLOT_FIRST_PRIVATE_FD);
  close(ends[0]);
  close(ends[1]);
  if (read_end < 0 || write_end < 0 || read_end > 32767 || write_end > 32767) {
    if (read_end >= 0) close(read_end);
    if (write_end >= 0) close(write_end);
    return -1;
  }
  int flags = fcntl(write_end, F_GETFL);
  if (flags < 0 || fcntl(write_end, F_SETFL, flags | O_NONBLOCK) != 0) {
    close(read_end);
    close(write_end);
    return -1;
  }
  return (read_end << 16) | write_end;
}

// Append a suffix of one encoded frame, including its final newline.
// Nonnegative means the exact number written; -2 means busy/unavailable, and
// -1 means write failure. The caller retains any unfinished frame and offset.
int32_t actql_executor_slot_channel_write(
  int32_t descriptor,
  int32_t inspection_descriptor,
  moonbit_bytes_t frame,
  int32_t frame_length,
  int32_t offset
) {
  if (descriptor < 0 || inspection_descriptor < 0 || offset < 0 ||
      offset >= frame_length) return -1;
  if (offset == 0) {
    int unread = 0;
    // Inspect the read side without consuming it. Starting another frame
    // while bytes are unread would accumulate stale repeated offers.
    if (ioctl(inspection_descriptor, FIONREAD, &unread) != 0 || unread != 0)
      return -2;
  }
  while (true) {
    ssize_t count = write(descriptor, frame + offset,
      (size_t)(frame_length - offset));
    if (count > 0) return (int32_t)count;
    if (count < 0 && errno == EINTR) continue;
    if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return -2;
    return -1;
  }
}

// Read one line from standard input, at most max_bytes. The first byte of the
// result is 'L' followed by the line, 'E' at end of input, or 'X' when the
// line is too long or reading failed.
moonbit_bytes_t actql_executor_slot_read_input_line(int32_t max_bytes) {
  if (max_bytes < 1) max_bytes = 1;
  char *buffer = malloc((size_t)max_bytes + 1);
  if (buffer == NULL) {
    moonbit_bytes_t failed = moonbit_make_bytes_raw(1);
    failed[0] = 'X';
    return failed;
  }
  int32_t length = 0;
  char status = 'L';
  while (true) {
    char byte;
    ssize_t count = read(0, &byte, 1);
    if (count < 0) {
      if (errno == EINTR) continue;
      status = 'X';
      break;
    }
    if (count == 0) {
      if (length == 0) status = 'E';
      break;
    }
    if (byte == '\n') break;
    if (length == max_bytes) {
      status = 'X';
      break;
    }
    buffer[length] = byte;
    length += 1;
  }
  int32_t returned = status == 'L' ? length : 0;
  moonbit_bytes_t result = moonbit_make_bytes_raw(returned + 1);
  result[0] = (uint8_t)status;
  if (returned > 0) memcpy(result + 1, buffer, (size_t)returned);
  free(buffer);
  return result;
}

// Acceptance evidence only: ends this process at once with SIGKILL, as an
// abrupt external kill would, without running any cleanup.
int32_t actql_executor_slot_kill_self(void) {
  kill(getpid(), SIGKILL);
  return -1;
}
