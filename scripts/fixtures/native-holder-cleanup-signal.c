// Exact executor-slot FFI, not a MoonBit Host/Provider or cleanup-ACK test.
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include <sys/select.h>
static int fixture_pselect(int, fd_set *, fd_set *, fd_set *,
                           const struct timespec *, const sigset_t *);
#define pselect fixture_pselect
#include "../../src/platform_native/executor_slot/executor_slot_stub.c"
#undef pselect
#include <assert.h>
#include <stdio.h>

static bool inject_between_check_and_wait = false;
static int fixture_pselect(int width, fd_set *readable, fd_set *writeable,
                           fd_set *exceptional, const struct timespec *timeout,
                           const sigset_t *mask) {
  if (inject_between_check_and_wait) {
    inject_between_check_and_wait = false;
    assert(raise(SIGTERM) == 0);
  }
  return pselect(width, readable, writeable, exceptional, timeout, mask);
}

static volatile sig_atomic_t unrelated_signals = 0;
static void on_unrelated(int number) {
  (void)number;
  unrelated_signals += 1;
}

static void delay_signal(void) {
  struct timespec remaining = { .tv_sec = 0, .tv_nsec = 50000000 };
  while (nanosleep(&remaining, &remaining) != 0) assert(errno == EINTR);
}

// A marker written before the watched signal distinguishes blocking until the
// new event from an immediate return on the old termination flag. Only this
// fixture's child is signalled/waited; every child is reaped before assertions.
static pid_t signal_child(int *marker, bool unrelated_first) {
  int ends[2];
  assert(pipe(ends) == 0);
  assert(fcntl(ends[0], F_SETFL, O_NONBLOCK) == 0);
  pid_t child = fork();
  assert(child >= 0);
  if (child == 0) {
    close(ends[0]);
    if (unrelated_first) {
      delay_signal();
      if (kill(getppid(), SIGUSR1) != 0) _exit(1);
    }
    delay_signal();
    if (write(ends[1], "w", 1) != 1) _exit(2);
    if (kill(getppid(), SIGINT) != 0) _exit(3);
    close(ends[1]);
    _exit(0);
  }
  close(ends[1]);
  *marker = ends[0];
  return child;
}

static void reaped_marker(pid_t child, int marker, bool observed_before_reap) {
  int status;
  assert(waitpid(child, &status, 0) == child);
  assert(close(marker) == 0);
  assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
  assert(observed_before_reap);
}

static bool marker_present(int marker) {
  char byte = 0;
  return read(marker, &byte, 1) == 1 && byte == 'w';
}

static void passed(const char *name) {
  printf("PASS %s\n", name);
  fflush(stdout);
}

int main(void) {
  assert(actql_executor_slot_install_termination() == 0);
  assert(raise(SIGTERM) == 0);
  assert(actql_executor_slot_termination_requested() == 1);
  assert(actql_executor_slot_wait_cleanup_signal() == 0);
  assert(actql_executor_slot_cleanup_wake == 0);
  assert(actql_executor_slot_termination_requested() == 1);
  passed("prelatched wake consumed without clearing termination");

  int marker;
  pid_t child = signal_child(&marker, false);
  int waited = actql_executor_slot_wait_cleanup_signal();
  bool new_event = marker_present(marker);
  reaped_marker(child, marker, new_event);
  assert(waited == 0);
  assert(actql_executor_slot_termination_requested() == 1);
  passed("already-true termination blocks until a new signal");

  sigset_t watched, previous, current;
  sigemptyset(&watched);
  sigaddset(&watched, SIGTERM);
  assert(sigprocmask(SIG_BLOCK, &watched, &previous) == 0);
  assert(raise(SIGTERM) == 0);
  assert(actql_executor_slot_cleanup_wake == 0);
  assert(actql_executor_slot_wait_cleanup_signal() == 0);
  assert(sigprocmask(SIG_SETMASK, NULL, &current) == 0);
  assert(sigismember(&current, SIGTERM) == 1);
  assert(sigprocmask(SIG_SETMASK, &previous, NULL) == 0);
  passed("masked pending signal delivered atomically and original mask restored");

  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = on_unrelated;
  sigemptyset(&action.sa_mask);
  assert(sigaction(SIGUSR1, &action, NULL) == 0);
  child = signal_child(&marker, true);
  waited = actql_executor_slot_wait_cleanup_signal();
  new_event = marker_present(marker);
  reaped_marker(child, marker, new_event);
  assert(waited == 0 && unrelated_signals == 1);
  passed("unrelated signal cannot complete the watched wait");

  int original_input = dup(STDIN_FILENO);
  assert(original_input >= 0);
  int input[2];
  assert(pipe(input) == 0);
  assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
  assert(close(input[0]) == 0);
  assert(close(input[1]) == 0);
  actql_executor_slot_terminate_flag = 0;
  moonbit_bytes_t result = actql_executor_slot_read_input_line(32);
  assert(result[0] == 'E');
  moonbit_decref(result);
  passed("actual channel EOF returns ended rather than a progress frame");

  assert(pipe(input) == 0);
  assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
  assert(close(input[0]) == 0);
  assert(raise(SIGTERM) == 0);
  result = actql_executor_slot_read_input_line(32);
  assert(result[0] == 'X');
  moonbit_decref(result);
  assert(actql_executor_slot_wait_cleanup_signal() == 0);
  assert(close(input[1]) == 0);
  passed("termination before channel read cannot block for a second signal");

  assert(pipe(input) == 0);
  assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
  assert(close(input[0]) == 0);
  actql_executor_slot_terminate_flag = 0;
  child = signal_child(&marker, false);
  result = actql_executor_slot_read_input_line(32);
  new_event = marker_present(marker);
  reaped_marker(child, marker, new_event);
  assert(result[0] == 'X');
  moonbit_decref(result);
  assert(close(input[1]) == 0);
  passed("termination during blocked read returns to the pending lifetime");

  assert(pipe(input) == 0);
  assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
  assert(close(input[0]) == 0);
  actql_executor_slot_terminate_flag = 0;
  inject_between_check_and_wait = true;
  result = actql_executor_slot_read_input_line(32);
  assert(!inject_between_check_and_wait && result[0] == 'X');
  moonbit_decref(result);
  assert(close(input[1]) == 0);
  assert(dup2(original_input, STDIN_FILENO) == STDIN_FILENO);
  assert(actql_executor_slot_termination_requested() == 1);
  passed("signal queued between read flag check and atomic wait is not lost");

  actql_executor_slot_terminate_flag = 0;
  assert(pipe(input) == 0);
  assert(write(input[1], "ok\n", 3) == 3);
  assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
  assert(close(input[0]) == 0);
  result = actql_executor_slot_read_input_line(2);
  assert(result[0] == 'L' && result[1] == 'o' && result[2] == 'k');
  moonbit_decref(result);
  assert(close(input[1]) == 0);
  passed("ordinary exact-limit channel frame remains readable");

  assert(pipe(input) == 0);
  assert(write(input[1], "bad\n", 4) == 4);
  assert(dup2(input[0], STDIN_FILENO) == STDIN_FILENO);
  assert(close(input[0]) == 0);
  result = actql_executor_slot_read_input_line(2);
  assert(result[0] == 'X');
  moonbit_decref(result);
  assert(close(input[1]) == 0);
  assert(dup2(original_input, STDIN_FILENO) == STDIN_FILENO);
  assert(close(original_input) == 0);
  passed("ordinary one-over-limit channel frame remains refused");
  return 0;
}
