/* Included once in the existing filesystem stub, before allocation macros. */
#include "native_timings.h"
#include <errno.h>
#include <inttypes.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define ACTQL_TIMING_PHASES 39
#define ACTQL_TIMING_STACK 32
#define ACTQL_TIMING_COUNTERS 66
/* 0 unselected, 1 selecting, 2 disabled, 3 enabled. Never wait on another
 * thread or an inherited initialization. Missed diagnostic entries are named. */
static _Atomic int actql_timing_selection;
static pid_t actql_timing_process;
static uint64_t actql_timing_origin;
static _Atomic uint64_t actql_timing_initializing_drops;
static _Atomic uint64_t actql_timing_invalid_tags;
static _Atomic uint64_t actql_timing_invalid_amounts;
static _Atomic uint64_t actql_timing_clock_failures;
static _Atomic uint64_t actql_timing_stack_overflows;
static _Atomic uint64_t actql_timing_flights;
static _Atomic bool actql_timing_parallel;
static _Atomic bool actql_timing_overflow;
static _Atomic uint64_t actql_timing_counts[ACTQL_TIMING_COUNTERS];
static _Atomic uint64_t actql_timing_begins[ACTQL_TIMING_PHASES];
static _Atomic uint64_t actql_timing_ends[ACTQL_TIMING_PHASES];
static _Atomic uint64_t actql_timing_elapsed[ACTQL_TIMING_PHASES];
static _Atomic uint64_t actql_timing_active[ACTQL_TIMING_PHASES];
static _Atomic uint64_t actql_timing_overlap[ACTQL_TIMING_PHASES];
static _Atomic uint64_t actql_timing_unmatched[ACTQL_TIMING_PHASES];
static _Atomic uint64_t actql_timing_exclusive[ACTQL_TIMING_PHASES];
static _Atomic uint64_t actql_timing_phase_sql[ACTQL_TIMING_PHASES];
static _Atomic uint64_t actql_timing_phase_current[ACTQL_TIMING_PHASES];
/* Fixed metadata only: no paths, payloads, borrowed pointers or heap storage. */
#define ACTQL_ACCEPTANCE_EVENTS 32
typedef struct { int32_t tag, ordinal; char identity[72]; _Atomic bool ready; } actql_acceptance_event;
static actql_acceptance_event actql_acceptance_events[ACTQL_ACCEPTANCE_EVENTS];
static _Atomic unsigned actql_acceptance_count;
static _Atomic bool actql_acceptance_invalid;
static bool actql_acceptance_selected;
typedef struct { int32_t tag; uint64_t start, child_ns, sql_start, current_start; } actql_timing_frame;
static _Thread_local actql_timing_frame actql_timing_stack[ACTQL_TIMING_STACK];
static _Thread_local uint32_t actql_timing_depth;
static _Thread_local uint64_t actql_timing_dropped_depth;

static void actql_timing_add(_Atomic uint64_t *target, uint64_t delta) {
  uint64_t previous = atomic_fetch_add_explicit(target, delta, memory_order_relaxed);
  if (previous > UINT64_MAX - delta)
    atomic_store_explicit(&actql_timing_overflow, true, memory_order_relaxed);
}
static bool actql_timing_now(uint64_t *result) {
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0 || value.tv_sec < 0 ||
      (uint64_t)value.tv_sec > (UINT64_MAX - 999999999) / 1000000000) {
    actql_timing_add(&actql_timing_clock_failures, 1);
    return false;
  }
  *result = (uint64_t)value.tv_sec * 1000000000 + (uint64_t)value.tv_nsec;
  return true;
}
static const char *actql_timing_phase_name(int tag) {
  static const char *const names[] = {"startup", "config_auth", "preparation",
    "execution", "save", "close", "saved_result", "journal"};
  if (tag < 8) return names[tag];
  switch (tag) {
    case 32: return "approval_material_complete";
    case 33: return "approval_reviewer_sign";
    case 34: return "approval_host_sign";
    case 35: return "approval_resolution_commit";
    case 36: return "approval_apply";
    case 37: return "approval_publish";
    case 38: return "approval_checkpoint_restore";
    default: return "private_phase";
  }
}
static const char *actql_timing_counter_name(int tag) {
  switch (tag) {
    case ACTQL_NATIVE_COUNT_SQL_OPEN: return "sqlite_open_calls";
    case ACTQL_NATIVE_COUNT_SQL_QUERY: return "sqlite_prepare_calls";
    case ACTQL_NATIVE_COUNT_SQL_EXEC: return "sqlite_exec_calls";
    case ACTQL_NATIVE_COUNT_SQL_STEP: return "sqlite_step_calls";
    case ACTQL_NATIVE_COUNT_MEMBER_HASH: return "member_hash_calls";
    case ACTQL_NATIVE_COUNT_PARSE_CHECK: return "parse_check_calls";
    case ACTQL_NATIVE_COUNT_CURRENT: return "current_calls";
    case ACTQL_NATIVE_COUNT_ACCOUNT_AUTH: return "account_auth_calls";
    case ACTQL_NATIVE_COUNT_RUN_RECORD_SAVE: return "run_record_save_calls";
    case ACTQL_NATIVE_COUNT_HOST_AUTH: return "host_authorize_calls";
    case ACTQL_NATIVE_COUNT_CAPTURED_READ_AUTH: return "captured_read_authorize_calls";
    case ACTQL_NATIVE_COUNT_PUBLISHER_AUTH: return "publisher_authorize_calls";
    case ACTQL_NATIVE_COUNT_RUN_RECORD_READ: return "run_record_read_calls";
    case ACTQL_NATIVE_COUNT_ADOPTION_DIGEST: return "adoption_digest_calls";
    case ACTQL_NATIVE_COUNT_BACKING_ALLOCATED_BYTES: return "backing_allocated_bytes";
    case ACTQL_NATIVE_COUNT_BACKING_ZEROED_BYTES: return "backing_explicit_zeroed_bytes";
    case ACTQL_NATIVE_COUNT_SIGNING_FULL_BOUNDARY: return "signing_full_boundary_calls";
    case ACTQL_NATIVE_COUNT_SIGNING_HELPER_REVALIDATION: return "signing_helper_revalidation_calls";
    default: return "private_counter";
  }
}
/* Never change the application's SIGPIPE disposition or shared FD flags.
 * A bounded buffer and immediate readiness checks allow diagnostics to truncate.
 * Missing rows are not zero counts or a successful complete measurement. */
static void actql_timing_emit(const char *body, size_t bytes) {
  sigset_t pipe_signal, original_mask, pending;
  sigemptyset(&pipe_signal); sigaddset(&pipe_signal, SIGPIPE);
  if (pthread_sigmask(SIG_BLOCK, &pipe_signal, &original_mask) != 0) return;
  bool previously_pending = sigpending(&pending) != 0 || sigismember(&pending, SIGPIPE) == 1;
  struct stat destination;
  bool socket = fstat(STDERR_FILENO, &destination) == 0 && S_ISSOCK(destination.st_mode);
  bool own_pipe_failure = false;
  size_t sent = 0;
  while (sent < bytes) {
    struct pollfd output = {STDERR_FILENO, POLLOUT, 0};
    if (poll(&output, 1, 0) != 1 || (output.revents & (POLLERR | POLLHUP | POLLNVAL)) ||
        !(output.revents & POLLOUT)) break;
    /* At most the POSIX atomic pipe-write minimum, never a large stdio flush.
     * Socket writes additionally select per-call nonblocking semantics. */
    size_t count = bytes - sent < 512 ? bytes - sent : 512;
    ssize_t written = socket ? send(STDERR_FILENO, body + sent, count, MSG_DONTWAIT)
      : write(STDERR_FILENO, body + sent, count);
    if (written <= 0) { own_pipe_failure = written < 0 && errno == EPIPE; break; }
    sent += (size_t)written;
  }
  /* A synchronous EPIPE creates this thread's blocked SIGPIPE. Consume only a
   * newly pending signal after our own failed write, retaining a prior pending
   * application signal. No process-global handler or disposition is changed. */
  if (own_pipe_failure && !previously_pending && sigpending(&pending) == 0 &&
      sigismember(&pending, SIGPIPE) == 1) {
    int signal_number;
    (void)sigwait(&pipe_signal, &signal_number);
  }
  (void)pthread_sigmask(SIG_SETMASK, &original_mask, NULL);
}
#define ACTQL_TIMING_LOAD(value) atomic_load_explicit(&(value), memory_order_relaxed)
static void actql_timing_report(void) {
  int saved_errno = errno;
  /* Forked children inherit a snapshot, not a second report of the parent.
   * Child work is explicitly outside these original-process counters. */
  if (getpid() != actql_timing_process) { errno = saved_errno; return; }
  uint64_t now = actql_timing_origin;
  bool clock_current = actql_timing_now(&now);
  char body[32768];
  size_t used = 0;
#define ACTQL_TIMING_APPEND(...) do { \
    int actql_timing_append_bytes = snprintf(body + used, sizeof(body) - used, __VA_ARGS__); \
    if (actql_timing_append_bytes < 0 || (size_t)actql_timing_append_bytes >= sizeof(body) - used) { errno = saved_errno; return; } \
    used += (size_t)actql_timing_append_bytes; \
  } while (0)
  ACTQL_TIMING_APPEND("ACTQL_NATIVE_TIMINGS {\"pid\":%ld,\"origin\":\"first_hook\","
    "\"elapsed_ns\":%" PRIu64 ",\"clock_current\":%s,\"nested_inclusive\":true,"
    "\"child_process_counters\":false,\"phase_slots\":39,\"counter_slots\":66,\"initializing_drops\":%" PRIu64 ","
    "\"invalid_tags\":%" PRIu64 ",\"invalid_amounts\":%" PRIu64 ",\"clock_failures\":%" PRIu64 ",\"overflow\":%s,"
    "\"stack_overflows\":%" PRIu64 ",\"parallel_observed\":%s}\n",
    (long)actql_timing_process, now >= actql_timing_origin ? now - actql_timing_origin : 0,
    clock_current ? "true" : "false", ACTQL_TIMING_LOAD(actql_timing_initializing_drops),
    ACTQL_TIMING_LOAD(actql_timing_invalid_tags), ACTQL_TIMING_LOAD(actql_timing_invalid_amounts),
    ACTQL_TIMING_LOAD(actql_timing_clock_failures),
    ACTQL_TIMING_LOAD(actql_timing_overflow) ? "true" : "false",
    ACTQL_TIMING_LOAD(actql_timing_stack_overflows),
    ACTQL_TIMING_LOAD(actql_timing_parallel) ? "true" : "false");
  for (int tag = 0; tag < ACTQL_TIMING_PHASES; tag++) {
    uint64_t begin = ACTQL_TIMING_LOAD(actql_timing_begins[tag]);
    uint64_t unmatched = ACTQL_TIMING_LOAD(actql_timing_unmatched[tag]);
    ACTQL_TIMING_APPEND("ACTQL_NATIVE_PHASE {\"tag\":%d,\"name\":\"%s\","
        "\"begins\":%" PRIu64 ",\"ends\":%" PRIu64 ",\"inclusive_ns\":%" PRIu64 ",\"exclusive_ns\":%" PRIu64 ","
        "\"active\":%" PRIu64 ",\"overlap\":%" PRIu64 ",\"unmatched_end\":%" PRIu64 ",\"sql_prepares\":%" PRIu64 ",\"current_calls\":%" PRIu64 "}\n",
        tag, actql_timing_phase_name(tag), begin, ACTQL_TIMING_LOAD(actql_timing_ends[tag]),
        ACTQL_TIMING_LOAD(actql_timing_elapsed[tag]), ACTQL_TIMING_LOAD(actql_timing_exclusive[tag]),
        ACTQL_TIMING_LOAD(actql_timing_active[tag]),
        ACTQL_TIMING_LOAD(actql_timing_overlap[tag]), unmatched,
        ACTQL_TIMING_LOAD(actql_timing_phase_sql[tag]), ACTQL_TIMING_LOAD(actql_timing_phase_current[tag]));
  }
  for (int tag = 0; tag < ACTQL_TIMING_COUNTERS; tag++) {
    uint64_t count = ACTQL_TIMING_LOAD(actql_timing_counts[tag]);
    ACTQL_TIMING_APPEND("ACTQL_NATIVE_COUNTER {\"tag\":%d,\"name\":\"%s\","
      "\"count\":%" PRIu64 "}\n", tag, actql_timing_counter_name(tag), count);
  }
  if (actql_acceptance_selected) {
    unsigned total = atomic_load_explicit(&actql_acceptance_count, memory_order_acquire);
    bool complete = total <= ACTQL_ACCEPTANCE_EVENTS && !ACTQL_TIMING_LOAD(actql_acceptance_invalid);
    unsigned count = total > ACTQL_ACCEPTANCE_EVENTS ? ACTQL_ACCEPTANCE_EVENTS : total;
    for (unsigned index = 0; index < count; index++)
      if (!atomic_load_explicit(&actql_acceptance_events[index].ready, memory_order_acquire)) complete = false;
    ACTQL_TIMING_APPEND("ACTQL_NATIVE_ACCEPTANCE_BEGIN {\"pid\":%ld,\"count\":%u,\"limit\":32,\"complete\":%s}\n",
      (long)actql_timing_process, count, complete ? "true" : "false");
    for (unsigned index = 0; index < count; index++) {
      actql_acceptance_event *event = &actql_acceptance_events[index];
      if (!atomic_load_explicit(&event->ready, memory_order_acquire)) continue;
      ACTQL_TIMING_APPEND("ACTQL_NATIVE_ACCEPTANCE_EVENT {\"pid\":%ld,\"seq\":%u,\"tag\":%d,\"ordinal\":%d,\"identity\":\"%s\"}\n",
        (long)actql_timing_process, index, event->tag, event->ordinal, event->identity);
    }
    ACTQL_TIMING_APPEND("ACTQL_NATIVE_ACCEPTANCE_END {\"pid\":%ld,\"count\":%u}\n", (long)actql_timing_process, count);
  }
  actql_timing_emit(body, used);
#undef ACTQL_TIMING_APPEND
  errno = saved_errno;
}
static bool actql_timing_enabled(void) {
  int selected = atomic_load_explicit(&actql_timing_selection, memory_order_acquire);
  if (selected == 0) {
    int expected = 0;
    if (atomic_compare_exchange_strong_explicit(&actql_timing_selection, &expected, 1,
        memory_order_acq_rel, memory_order_acquire)) {
      const char *value = getenv("ACTQL_NATIVE_TIMINGS");
      bool enabled = value && strcmp(value, "1") == 0;
      const char *acceptance = getenv("ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS");
      actql_acceptance_selected = enabled && acceptance && strcmp(acceptance, "1") == 0;
      actql_timing_process = getpid();
      if (enabled && (!actql_timing_now(&actql_timing_origin) || atexit(actql_timing_report) != 0))
        enabled = false;
      selected = enabled ? 3 : 2;
      atomic_store_explicit(&actql_timing_selection, selected, memory_order_release);
    } else selected = expected;
  }
  if (selected == 1) actql_timing_add(&actql_timing_initializing_drops, 1);
  return selected == 3;
}
int32_t actql_native_acceptance_enabled(void) {
  int saved_errno = errno;
  bool enabled = actql_timing_enabled() && actql_acceptance_selected && getpid() == actql_timing_process;
  errno = saved_errno;
  return enabled;
}
void actql_native_acceptance_incomplete(void) {
  int saved_errno = errno;
  if (actql_native_acceptance_enabled()) atomic_store_explicit(&actql_acceptance_invalid, true, memory_order_relaxed);
  errno = saved_errno;
}
static actql_acceptance_event *actql_acceptance_next(void) {
  unsigned index = atomic_load_explicit(&actql_acceptance_count, memory_order_relaxed);
  while (index < ACTQL_ACCEPTANCE_EVENTS &&
      !atomic_compare_exchange_weak_explicit(&actql_acceptance_count, &index, index + 1,
        memory_order_relaxed, memory_order_relaxed)) {}
  if (index >= ACTQL_ACCEPTANCE_EVENTS) {
    atomic_store_explicit(&actql_acceptance_invalid, true, memory_order_relaxed);
    return NULL;
  }
  return &actql_acceptance_events[index];
}
void actql_native_acceptance_identity(int32_t tag, int32_t ordinal,
    const uint16_t *identity, int32_t length) {
  int saved_errno = errno;
  if (actql_native_acceptance_enabled()) {
    bool valid = tag >= 0 && tag <= 11 && tag != 6 && tag != 7 && ordinal >= 0 && identity && length == 71;
    const char *prefix = "sha256:";
    for (int index = 0; valid && index < 71; index++)
      valid = index < 7 ? identity[index] == (uint16_t)prefix[index]
        : ((identity[index] >= '0' && identity[index] <= '9') || (identity[index] >= 'a' && identity[index] <= 'f'));
    if (!valid) atomic_store_explicit(&actql_acceptance_invalid, true, memory_order_relaxed);
    else {
      actql_acceptance_event *event = actql_acceptance_next();
      if (event) {
        event->tag = tag; event->ordinal = ordinal;
        for (int index = 0; index < 71; index++) event->identity[index] = (char)identity[index];
        event->identity[71] = 0;
        atomic_store_explicit(&event->ready, true, memory_order_release);
      }
    }
  }
  errno = saved_errno;
}
void actql_native_acceptance_mutation(int32_t tag) {
  int saved_errno = errno;
  if (actql_native_acceptance_enabled()) {
    if (tag != 6 && tag != 7) atomic_store_explicit(&actql_acceptance_invalid, true, memory_order_relaxed);
    else {
      actql_acceptance_event *event = actql_acceptance_next();
      if (event) { event->tag = tag; event->ordinal = -1; event->identity[0] = 0;
        atomic_store_explicit(&event->ready, true, memory_order_release); }
    }
  }
  errno = saved_errno;
}
void actql_native_timing_amount(int32_t tag, int64_t amount) {
  int saved_errno = errno;
  if (actql_timing_enabled()) {
    if (amount < 0) actql_timing_add(&actql_timing_invalid_amounts, 1);
    else if (tag >= 0 && tag < ACTQL_TIMING_COUNTERS)
      actql_timing_add(&actql_timing_counts[tag], (uint64_t)amount);
    else actql_timing_add(&actql_timing_invalid_tags, 1);
  }
  errno = saved_errno;
}
void actql_native_timing_count(int32_t tag) {
  actql_native_timing_amount(tag, 1);
}
int64_t actql_native_timing_counter_value(int32_t tag) {
  int saved_errno = errno;
  int64_t result = -1;
  if (actql_timing_enabled() && getpid() == actql_timing_process &&
      tag >= 0 && tag < ACTQL_TIMING_COUNTERS &&
      !atomic_load_explicit(&actql_timing_overflow, memory_order_relaxed)) {
    uint64_t value = atomic_load_explicit(&actql_timing_counts[tag], memory_order_relaxed);
    if (value <= INT64_MAX) result = (int64_t)value;
  }
  errno = saved_errno;
  return result;
}
void actql_native_timing_begin(int32_t tag) {
  int saved_errno = errno;
  if (actql_timing_enabled()) {
    if (tag < 0 || tag >= ACTQL_TIMING_PHASES) actql_timing_add(&actql_timing_invalid_tags, 1);
    else {
      actql_timing_add(&actql_timing_begins[tag], 1);
      if (actql_timing_dropped_depth || actql_timing_depth == ACTQL_TIMING_STACK) {
        actql_timing_add(&actql_timing_stack_overflows, 1);
        if (actql_timing_dropped_depth != UINT64_MAX) actql_timing_dropped_depth++;
        else atomic_store_explicit(&actql_timing_overflow, true, memory_order_relaxed);
      } else {
        uint64_t now;
        if (actql_timing_now(&now)) {
          for (uint32_t i = 0; i < actql_timing_depth; i++)
            if (actql_timing_stack[i].tag == tag) { actql_timing_add(&actql_timing_overlap[tag], 1); break; }
          uint64_t previous = atomic_fetch_add_explicit(&actql_timing_flights, 1, memory_order_relaxed);
          if (previous > actql_timing_depth)
            atomic_store_explicit(&actql_timing_parallel, true, memory_order_relaxed);
          actql_timing_stack[actql_timing_depth++] = (actql_timing_frame){tag, now, 0,
            atomic_load_explicit(&actql_timing_counts[ACTQL_NATIVE_COUNT_SQL_QUERY], memory_order_relaxed),
            atomic_load_explicit(&actql_timing_counts[ACTQL_NATIVE_COUNT_CURRENT], memory_order_relaxed)};
          actql_timing_add(&actql_timing_active[tag], 1);
        }
      }
    }
  }
  errno = saved_errno;
}
void actql_native_timing_end(int32_t tag) {
  int saved_errno = errno;
  if (actql_timing_enabled()) {
    if (tag < 0 || tag >= ACTQL_TIMING_PHASES) actql_timing_add(&actql_timing_invalid_tags, 1);
    else if (actql_timing_dropped_depth) actql_timing_dropped_depth--;
    else if (actql_timing_depth == 0 || actql_timing_stack[actql_timing_depth - 1].tag != tag)
      actql_timing_add(&actql_timing_unmatched[tag], 1);
    else {
      actql_timing_frame frame = actql_timing_stack[actql_timing_depth - 1];
      uint64_t now;
      if (actql_timing_now(&now) && now >= frame.start) {
        uint64_t duration = now - frame.start;
        actql_timing_add(&actql_timing_elapsed[tag], duration);
        if (duration >= frame.child_ns) actql_timing_add(&actql_timing_exclusive[tag], duration - frame.child_ns);
        else actql_timing_add(&actql_timing_clock_failures, 1);
        /* Process-counter deltas are inclusive like the containing phase.
         * parallel_observed labels overlap; these are not exclusive SQL costs. */
        uint64_t sql = atomic_load_explicit(&actql_timing_counts[ACTQL_NATIVE_COUNT_SQL_QUERY], memory_order_relaxed);
        uint64_t current = atomic_load_explicit(&actql_timing_counts[ACTQL_NATIVE_COUNT_CURRENT], memory_order_relaxed);
        if (sql >= frame.sql_start && current >= frame.current_start) {
          actql_timing_add(&actql_timing_phase_sql[tag], sql - frame.sql_start);
          actql_timing_add(&actql_timing_phase_current[tag], current - frame.current_start);
        } else atomic_store_explicit(&actql_timing_overflow, true, memory_order_relaxed);
        actql_timing_depth--;
        if (actql_timing_depth) {
          uint64_t *child = &actql_timing_stack[actql_timing_depth - 1].child_ns;
          if (*child > UINT64_MAX - duration) atomic_store_explicit(&actql_timing_overflow, true, memory_order_relaxed);
          else *child += duration;
        }
        actql_timing_add(&actql_timing_ends[tag], 1);
        atomic_fetch_sub_explicit(&actql_timing_active[tag], 1, memory_order_relaxed);
        atomic_fetch_sub_explicit(&actql_timing_flights, 1, memory_order_relaxed);
      }
    }
  }
  errno = saved_errno;
}
#undef ACTQL_TIMING_LOAD
