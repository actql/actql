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
  ACTQL_NATIVE_COUNT_ADOPTION_DIGEST = 26,
  ACTQL_NATIVE_COUNT_BACKING_ALLOCATED_BYTES = 46,
  ACTQL_NATIVE_COUNT_BACKING_ZEROED_BYTES = 47,
  ACTQL_NATIVE_COUNT_SIGNING_FULL_BOUNDARY = 64,
  ACTQL_NATIVE_COUNT_SIGNING_HELPER_REVALIDATION = 65
};
void actql_native_timing_begin(int32_t tag);
void actql_native_timing_end(int32_t tag);
void actql_native_timing_count(int32_t tag);
/* Read an existing process-local diagnostic counter without resetting it.
 * -1 means unavailable; it must never be interpreted as zero work. */
int64_t actql_native_timing_counter_value(int32_t tag);
/* Acceptance metadata is separate from numeric timing counters and authority. */
int32_t actql_native_acceptance_enabled(void);
void actql_native_acceptance_identity(int32_t tag, int32_t ordinal,
    const uint16_t *identity, int32_t length);
void actql_native_acceptance_incomplete(void);
void actql_native_acceptance_mutation(int32_t tag);

/* Add one already-observed nonnegative amount. Cumulative observations require
 * caller-selected deltas; this diagnostic neither reads nor owns a resource. */
void actql_native_timing_amount(int32_t tag, int64_t amount);

/* Evaluate the same function designator once; keep original arguments/result.
 * Counts describe attempted adapter calls, not SQLite-internal statements. */
#define ACTQL_NATIVE_TIMED_CALL(counter, function) \
  (actql_native_timing_count(counter), (function))
#endif
