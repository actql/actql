///|
test "native captured output converts without replay and preserves success across conversion exhaustion" {
  let f = native_issuer_fixture()
  let attempt = native_issued_attempt(f)
  native_attempt_receive_fixture(attempt)
  f.transport.push(attempt)
  let observation = @planning.complete_duckdb_native_capture(
    f.issuer,
    attempt,
    native_completion_limits(),
  ).unwrap()
  // Two {id:number} rows: one object and scalar each; id contributes 2 bytes
  // and 2 work plus one scalar visit per row. Numeric values add no text bytes.
  let exact : @execution.ValueLimits = {
    max_nodes: 4,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 8,
  }
  for
    limits in [
      { ..exact, max_nodes: 3, },
      { ..exact, max_text_bytes: 3, },
      { ..exact, max_work: 7, },
      { ..exact, max_depth: 1, },
    ] {
    assert_true(
      @planning.materialize_duckdb_native_output(
        f.issuer,
        attempt,
        observation,
        2,
        limits,
      )
      is Err(NativeOutput(Retention(CaptureLimit))),
    )
    assert_true(
      @planning.verify_duckdb_native_observation(f.issuer, attempt, observation)
      is Ok(_),
    )
  }
  assert_true(
    @planning.materialize_duckdb_native_output(
      f.issuer,
      attempt,
      observation,
      1,
      exact,
    )
    is Err(NativeOutput(Retention(CaptureLimit))),
  )
  let output = @planning.materialize_duckdb_native_output(
    f.issuer,
    attempt,
    observation,
    2,
    exact,
  ).unwrap()
  let rows = @planning.duckdb_native_output_rows(output).unwrap()
  assert_true(
    physical_equal(
      @execution.admitted_output_owner(rows),
      @duckdb.native_query_owner(
        @duckdb.native_scan_query(
          @planning.duckdb_native_preparation_scan(
            @planning.duckdb_native_attempt_preparation(attempt),
          ),
        ),
      ),
    ),
  )
  assert_eq(@execution.admitted_output_target(rows), @pipeline.Step(1))
  assert_eq(@execution.admitted_output_row_count(rows), 2)
  assert_true(
    @execution.admitted_output_cell(rows, 0, 0) is Some(@admitted.Number(3.0)),
  )
  assert_true(
    @execution.admitted_output_cell(rows, 1, 0) is Some(@admitted.Number(2.0)),
  )
  assert_eq(@execution.admitted_output_usage(rows), {
    nodes: 4,
    text_bytes: 4,
    work: 8,
  })
  let other = native_issuer_fixture()
  assert_true(
    @planning.materialize_duckdb_native_output(
      other.issuer,
      attempt,
      observation,
      2,
      exact,
    )
    is Err(_),
  )
  @planning.close_duckdb_native_issuer(f.issuer)
  assert_true(@planning.duckdb_native_output_rows(output) is Err(IssuerClosed))
}
