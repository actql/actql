///|
fn native_completion_limits() -> @planning.DuckDBNativeCompletionLimits {
  {
    demand: native_demand_physical(),
    receipts: native_attempt_wire(),
    max_received_rows: 5,
    max_received_bytes: 47,
    max_retained_wire_bytes: 47,
    records: query_material_limits(),
    capture: query_capture_limits(),
  }
}

///|
test "native Host completion owns sequencing without replacing the live verifier" {
  let f = native_issuer_fixture()
  let attempt = native_issued_attempt(f)
  native_attempt_receive_fixture(attempt)
  f.transport.push(attempt)
  let other = native_issuer_fixture()
  assert_true(
    @planning.complete_duckdb_native_capture(
      other.issuer,
      attempt,
      native_completion_limits(),
    )
    is Err(UnauthorizedAttempt),
  )
  // A foreign caller cannot poison the rightful attempt.
  let observation = @planning.complete_duckdb_native_capture(
    f.issuer,
    attempt,
    native_completion_limits(),
  ).unwrap()
  let (_, _, expected) = native_observation_oracle(
    f.requirement,
    @planning.duckdb_native_attempt_identity(attempt).unwrap(),
  )
  assert_eq(
    @planning.duckdb_native_observation_cid(observation),
    query_material_expected(expected),
  )
  assert_true(
    @planning.complete_duckdb_native_capture(
      f.issuer,
      attempt,
      native_completion_limits(),
    )
    is Err(AlreadyCaptured),
  )
  assert_true(
    @planning.verify_duckdb_native_observation(f.issuer, attempt, observation)
    is Ok(_),
  )
  f.transport.clear()
  assert_true(
    @planning.verify_duckdb_native_observation(f.issuer, attempt, observation)
    is Err(UnverifiedTransport),
  )
  let unverified = native_issued_attempt(f)
  native_attempt_receive_fixture(unverified)
  assert_true(
    @planning.complete_duckdb_native_capture(
      f.issuer,
      unverified,
      native_completion_limits(),
    )
    is Err(UnverifiedTransport),
  )
  f.transport.push(unverified)
  assert_true(
    @planning.complete_duckdb_native_capture(
      f.issuer,
      unverified,
      native_completion_limits(),
    )
    is Err(NativeAttempt(InvalidState)),
  )
  // Even a trusted transport match cannot substitute for the required receipts.
  let unfinished = native_issued_attempt(f)
  f.transport.push(unfinished)
  assert_true(
    @planning.complete_duckdb_native_capture(
      f.issuer,
      unfinished,
      native_completion_limits(),
    )
    is Err(NativeAttempt(InvalidState)),
  )
}

///|
test "native Host completion retains stage-specific limits and makes every failed attempt terminal" {
  let limits = native_completion_limits()
  for
    changed in [
      { ..limits, demand: { ..limits.demand, max_work: 0, }, },
      { ..limits, max_received_rows: 4, },
      { ..limits, max_received_bytes: 46, },
      { ..limits, max_retained_wire_bytes: 46, },
      { ..limits, records: { ..limits.records, max_bytes: 0, }, },
      { ..limits, capture: { ..limits.capture, max_bytes: 0, }, },
    ] {
    let f = native_issuer_fixture()
    let attempt = native_issued_attempt(f)
    native_attempt_receive_fixture(attempt)
    f.transport.push(attempt)
    assert_true(
      @planning.complete_duckdb_native_capture(f.issuer, attempt, changed)
      is Err(_),
    )
    assert_true(
      @planning.complete_duckdb_native_capture(f.issuer, attempt, limits)
      is Err(NativeAttempt(InvalidState)),
    )
    // Fresh budgets need a fresh execution, not resurrection of failed state.
    let retry = native_issued_attempt(f)
    native_attempt_receive_fixture(retry)
    f.transport.push(retry)
    assert_true(
      @planning.complete_duckdb_native_capture(f.issuer, retry, limits) is Ok(_),
    )
  }
}
