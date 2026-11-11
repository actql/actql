#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include "native_timings.inc"
#include <assert.h>
#include <pthread.h>
#include <sqlite3.h>
#include <sys/wait.h>

static struct sigaction original_pipe_action;
static sigset_t original_mask;
static void verify_original_signal_state(void) {
  struct sigaction current_action; sigset_t current_mask;
  assert(sigaction(SIGPIPE, NULL, &current_action) == 0);
  assert(current_action.sa_handler == original_pipe_action.sa_handler);
  assert(pthread_sigmask(SIG_SETMASK, NULL, &current_mask) == 0);
  assert(sigismember(&current_mask, SIGPIPE) == sigismember(&original_mask, SIGPIPE));
}
static void *worker(void *unused) {
  (void)unused;
  actql_native_timing_begin(ACTQL_NATIVE_PHASE_PREPARATION);
  for (int i = 0; i < 1000; i++) actql_native_timing_count(16);
  actql_native_timing_end(ACTQL_NATIVE_PHASE_PREPARATION);
  return NULL;
}
static void sqlite_calls(void) {
  sqlite3 *database = NULL; sqlite3_stmt *query = NULL;
  int (*open_database)(const char *, sqlite3 **) = sqlite3_open;
  assert(ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_OPEN, open_database)(":memory:", &database) == SQLITE_OK);
  assert(ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_EXEC, sqlite3_exec)(database, "CREATE TABLE t(id); INSERT INTO t VALUES(17)", NULL, NULL, NULL) == SQLITE_OK);
  assert(ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, sqlite3_prepare_v2)(database, "SELECT id FROM t", -1, &query, NULL) == SQLITE_OK);
  assert(ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, sqlite3_step)(query) == SQLITE_ROW);
  assert(sqlite3_column_int(query, 0) == 17);
  assert(ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, sqlite3_step)(query) == SQLITE_DONE);
  assert(sqlite3_finalize(query) == SQLITE_OK);
  assert(sqlite3_close(database) == SQLITE_OK);
}
int main(int argc, char **argv) {
  assert(argc == 2);
  assert(sigaction(SIGPIPE, NULL, &original_pipe_action) == 0);
  assert(pthread_sigmask(SIG_SETMASK, NULL, &original_mask) == 0);
  /* Registered before the timing report: verify after its actual emission. */
  assert(atexit(verify_original_signal_state) == 0);
  errno = EDOM; actql_native_timing_begin(ACTQL_NATIVE_PHASE_STARTUP); assert(errno == EDOM);
  if (strncmp(argv[1], "acceptance", 10) == 0) {
    uint16_t identity[71];
    const char *text = "sha256:1111111111111111111111111111111111111111111111111111111111111111";
    for (int index = 0; index < 71; index++) identity[index] = text[index];
    errno = EDOM;
    for (int tag = 0; tag < 3; tag++) actql_native_acceptance_identity(tag, 0, identity, 71);
    actql_native_acceptance_identity(5, 0, identity, 71);
    actql_native_acceptance_mutation(6); actql_native_acceptance_mutation(7);
    actql_native_acceptance_identity(8, 0, identity, 71);
    assert(errno == EDOM);
    if (strcmp(argv[1], "acceptance-invalid") == 0) {
      identity[0] = 'P'; actql_native_acceptance_identity(1, 0, identity, 71);
    }
    if (strcmp(argv[1], "acceptance-overflow") == 0)
      for (int index = 0; index < 40; index++) actql_native_acceptance_mutation(6);
    /* The recorder owns its fixed copy and never retains a managed pointer. */
    for (int index = 0; index < 71; index++) identity[index] = 'X';
  } else if (strcmp(argv[1], "sql") == 0) {
    struct timespec pause = {0, 2000000};
    nanosleep(&pause, NULL);
    actql_native_timing_begin(ACTQL_NATIVE_PHASE_EXECUTION);
    sqlite_calls(); nanosleep(&pause, NULL);
    actql_native_timing_end(ACTQL_NATIVE_PHASE_EXECUTION);
  } else if (strcmp(argv[1], "approval-stages") == 0) {
    for (int tag = 32; tag < 39; tag++) {
      actql_native_timing_begin(tag);
      actql_native_timing_end(tag);
    }
    actql_native_timing_count(ACTQL_NATIVE_COUNT_SIGNING_FULL_BOUNDARY);
  } else if (strcmp(argv[1], "snapshot") == 0) {
    bool enabled = getenv("ACTQL_NATIVE_TIMINGS") && strcmp(getenv("ACTQL_NATIVE_TIMINGS"), "1") == 0;
    errno = EDOM;
    assert(actql_native_timing_counter_value(-1) == -1);
    assert(actql_native_timing_counter_value(70) == -1);
    int64_t before = actql_native_timing_counter_value(16);
    actql_native_timing_count(16);
    int64_t after = actql_native_timing_counter_value(16);
    assert(enabled ? (before == 0 && after == 1) : (before == -1 && after == -1));
    assert(actql_native_timing_counter_value(16) == after);
    assert(errno == EDOM);
  } else if (strcmp(argv[1], "request-work") == 0) {
    /* Project observed totals once, without pretending these fixture amounts
     * are execution of an actual Request parser/checker/compiler. */
    actql_native_timing_amount(ACTQL_NATIVE_COUNT_REQUEST_QUERY_PARSE, 2);
    actql_native_timing_amount(ACTQL_NATIVE_COUNT_REQUEST_QUERY_LOWER, 3);
    actql_native_timing_amount(ACTQL_NATIVE_COUNT_REQUEST_SEMANTIC_CHECK, 4);
    actql_native_timing_amount(ACTQL_NATIVE_COUNT_REQUEST_PROGRAM_COMPILE, 5);
  } else if (strcmp(argv[1], "threads") == 0) {
    pthread_t workers[4];
    for (int i = 0; i < 4; i++) assert(pthread_create(&workers[i], NULL, worker, NULL) == 0);
    for (int i = 0; i < 4; i++) assert(pthread_join(workers[i], NULL) == 0);
  } else if (strcmp(argv[1], "fork") == 0) {
    actql_native_timing_count(16);
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) { for (int i = 0; i < 5; i++) actql_native_timing_count(16); exit(0); }
    int status = -1; assert(waitpid(child, &status, 0) == child); assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
  } else if (strcmp(argv[1], "amount") == 0) {
    errno = EDOM;
    actql_native_timing_amount(ACTQL_NATIVE_COUNT_BACKING_ALLOCATED_BYTES, 512 * 1024 * 1024);
    actql_native_timing_amount(ACTQL_NATIVE_COUNT_BACKING_ALLOCATED_BYTES, 16384);
    actql_native_timing_amount(ACTQL_NATIVE_COUNT_BACKING_ZEROED_BYTES, 16384);
    actql_native_timing_amount(ACTQL_NATIVE_COUNT_BACKING_ZEROED_BYTES, 0);
    actql_native_timing_amount(ACTQL_NATIVE_COUNT_BACKING_ZEROED_BYTES, -1);
    actql_native_timing_amount(70, 1);
    assert(errno == EDOM);
  } else if (strcmp(argv[1], "amount-overflow") == 0) {
    for (int i = 0; i < 3; i++)
      actql_native_timing_amount(ACTQL_NATIVE_COUNT_BACKING_ALLOCATED_BYTES, INT64_MAX);
  } else if (strcmp(argv[1], "partial") == 0) {
    for (int i = 0; i < 34; i++) actql_native_timing_begin(4);
    for (int i = 0; i < 34; i++) actql_native_timing_end(4);
    actql_native_timing_end(5);
    actql_native_timing_count(-1);
    actql_native_timing_begin(6); /* deliberately pending diagnostic only */
    return 0;
  } else assert(0);
  errno = ERANGE; actql_native_timing_end(ACTQL_NATIVE_PHASE_STARTUP); assert(errno == ERANGE);
  return 0;
}
