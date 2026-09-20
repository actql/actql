///|
test "managed DuckDB failure progression keeps physical facts independent" {
  let progress = begin_managed_duckdb_failure_progress(
    false, false, false, false, false, false, false,
  )
  assert_eq(managed_duckdb_failure_progress_action_code(progress), 0)
  assert_true(record_managed_duckdb_output_cancel_attempted(progress))
  assert_eq(managed_duckdb_failure_progress_action_code(progress), 1)
  assert_true(record_managed_duckdb_output_owners_close_attempted(progress))
  assert_eq(managed_duckdb_failure_progress_action_code(progress), 2)
  assert_true(record_managed_duckdb_output_reclaim_attempted(progress))
  assert_eq(managed_duckdb_failure_progress_action_code(progress), 3)
  assert_true(record_managed_duckdb_execution_close_attempted(progress))
  assert_eq(managed_duckdb_failure_progress_action_code(progress), 4)
  assert_true(
    record_managed_duckdb_failure_observations(progress, true, false, true),
  )
  assert_eq(managed_duckdb_failure_progress_action_code(progress), 5)
  assert_true(
    record_managed_duckdb_failure_observations(progress, false, true, false),
  )
  assert_eq(managed_duckdb_failure_progress_action_code(progress), 6)
  assert_true(record_managed_duckdb_execution_cleanup_confirmed(progress))
  assert_eq(managed_duckdb_failure_progress_action_code(progress), 8)
}

///|
test "managed DuckDB failure progress retains an output cleanup wait" {
  let progress = begin_managed_duckdb_failure_progress(
    true, true, true, true, true, true, false,
  )
  assert_true(record_managed_duckdb_output_owners_close_attempted(progress))
  assert_eq(managed_duckdb_failure_progress_action_code(progress), 7)
  assert_true(
    record_managed_duckdb_failure_observations(progress, false, false, true),
  )
  assert_eq(managed_duckdb_failure_progress_action_code(progress), 8)
}

///|
test "managed DuckDB cleanup retries every live owner independently" {
  let retry = begin_managed_duckdb_failure_retry_progress()
  assert_eq(
    managed_duckdb_failure_retry_progress_action_code(retry, true, true),
    0,
  )
  assert_true(record_managed_duckdb_native_retry_attempted(retry))
  assert_eq(
    managed_duckdb_failure_retry_progress_action_code(retry, true, true),
    1,
  )
  assert_true(record_managed_duckdb_output_retry_attempted(retry))
  assert_eq(
    managed_duckdb_failure_retry_progress_action_code(retry, true, true),
    2,
  )
  assert_eq(
    managed_duckdb_failure_retry_progress_action_code(retry, false, false),
    2,
  )
}
