#ifndef ACTQL_NATIVE_TIMINGS_H
#define ACTQL_NATIVE_TIMINGS_H
#include <stdint.h>

/* Opt-in diagnostics only. No return value can supply admission or an ACK. */
enum {
  ACTQL_NATIVE_PHASE_STARTUP = 0,
  ACTQL_NATIVE_PHASE_CONFIG_AUTH = 1,
  ACTQL_NATIVE_PHASE_PREPARATION = 2,
  ACTQL_NATIVE_PHASE_EXECUTION = 3,
  ACTQL_NATIVE_PHASE_SAVE = 4,
  ACTQL_NATIVE_PHASE_CLOSE = 5,
  ACTQL_NATIVE_PHASE_SAVED_RESULT = 6,
  ACTQL_NATIVE_PHASE_JOURNAL = 7
};
enum {
  ACTQL_NATIVE_COUNT_SQL_OPEN = 0,
  ACTQL_NATIVE_COUNT_SQL_QUERY = 1,
  ACTQL_NATIVE_COUNT_SQL_STEP = 2,
  ACTQL_NATIVE_COUNT_SQL_EXEC = 3,
  ACTQL_NATIVE_COUNT_MEMBER_HASH = 16,
  ACTQL_NATIVE_COUNT_PARSE_CHECK = 17,
  ACTQL_NATIVE_COUNT_CURRENT = 18,
  ACTQL_NATIVE_COUNT_ACCOUNT_AUTH = 19,
  ACTQL_NATIVE_COUNT_RUN_RECORD_SAVE = 20,
  ACTQL_NATIVE_COUNT_HOST_AUTH = 22,
  ACTQL_NATIVE_COUNT_CAPTURED_READ_AUTH = 23,
  ACTQL_NATIVE_COUNT_PUBLISHER_AUTH = 24,
  ACTQL_NATIVE_COUNT_RUN_RECORD_READ = 25,
  ACTQL_NATIVE_COUNT_ADOPTION_DIGEST = 26
};
void actql_native_timing_begin(int32_t tag);
void actql_native_timing_end(int32_t tag);
void actql_native_timing_count(int32_t tag);

/* Evaluate the same function designator once; keep original arguments/result.
 * Counts describe attempted adapter calls, not SQLite-internal statements. */
#define ACTQL_NATIVE_TIMED_CALL(counter, function) \
  (actql_native_timing_count(counter), (function))
#endif
