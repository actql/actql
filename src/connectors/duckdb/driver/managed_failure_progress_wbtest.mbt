///|
test "managed DuckDB failure progression keeps physical facts independent" {
  assert_eq(
    managed_duckdb_failure_step_code(
      false, false, false, false, false, false, false, false,
    ),
    0,
  )
  assert_eq(
    managed_duckdb_failure_step_code(
      true, false, false, false, false, false, false, false,
    ),
    1,
  )
  assert_eq(
    managed_duckdb_failure_step_code(
      true, true, false, false, false, false, false, false,
    ),
    2,
  )
  assert_eq(
    managed_duckdb_failure_step_code(
      true, true, true, false, false, false, false, false,
    ),
    3,
  )
  assert_eq(
    managed_duckdb_failure_step_code(
      true, true, true, true, false, false, false, true,
    ),
    4,
  )
  assert_eq(
    managed_duckdb_failure_step_code(
      true, true, true, true, true, false, false, false,
    ),
    5,
  )
  assert_eq(
    managed_duckdb_failure_step_code(
      true, true, true, true, true, true, false, false,
    ),
    6,
  )
  assert_eq(
    managed_duckdb_failure_step_code(
      true, true, true, true, true, true, true, false,
    ),
    7,
  )
  assert_eq(
    managed_duckdb_failure_step_code(
      true, true, true, true, true, true, true, true,
    ),
    8,
  )
}

///|
test "managed DuckDB cleanup retries every live owner independently" {
  assert_eq(managed_duckdb_failure_retry_step_code(true, false, true, false), 0)
  assert_eq(managed_duckdb_failure_retry_step_code(true, true, true, false), 1)
  assert_eq(managed_duckdb_failure_retry_step_code(true, true, true, true), 2)
  assert_eq(
    managed_duckdb_failure_retry_step_code(false, false, false, false),
    2,
  )
}
