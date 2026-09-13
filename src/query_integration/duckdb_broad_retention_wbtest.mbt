///|
fn completed_broad_attempt() -> @planning.DuckDBBroadAttempt raise {
  let attempt = broad_attempt_fixture()
  broad_attempt_receive(attempt)
  @planning.settle_duckdb_broad_transport(attempt).unwrap()
  @planning.execute_duckdb_broad_attempt(attempt, compute_test_limits(), {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  attempt
}

///|
test "DuckDB broad retention shares exact receipt and output measurement boundaries" {
  let exact : @planning.QueryRetentionLimits = {
    received_wire_bytes: 28,
    retained_wire_bytes: 47,
    measurement: {
      max_columns: 10,
      max_order_work: 1000,
      max_bytes: 47,
      max_nodes: 12,
      max_depth: 10,
    },
  }
  for nodes in [0, 7, 11, 12] {
    let attempt = completed_broad_attempt()
    let result = @planning.retain_duckdb_broad_attempt(attempt, {
      ..exact,
      measurement: { ..exact.measurement, max_nodes: nodes, },
    })
    if nodes == 12 {
      let retained = result.unwrap()
      assert_eq(@planning.duckdb_broad_retention_usage(retained), (28, 47, 12))
      assert_true(@planning.duckdb_broad_retention_matches(retained, attempt))
      assert_false(
        @planning.duckdb_broad_retention_matches(
          retained,
          completed_broad_attempt(),
        ),
      )
      @planning.abort_duckdb_broad_attempt(attempt)
      assert_false(@planning.duckdb_broad_retention_matches(retained, attempt))
      assert_true(@planning.duckdb_broad_attempt_output(attempt) is None)
    } else {
      if nodes == 0 {
        assert_true(result is Err(Retention(ScanIdentity(InvalidLimits))))
      } else {
        assert_true(
          result is Err(Retention(OutputIdentity(Encoding(OutputLimit)))),
        )
      }
      assert_true(@planning.duckdb_broad_attempt_output(attempt) is None)
      assert_true(
        @planning.retain_duckdb_broad_attempt(attempt, exact)
        is Err(InvalidState),
      )
    }
  }
  for bytes in [28, 46, 47] {
    let attempt = completed_broad_attempt()
    let result = @planning.retain_duckdb_broad_attempt(attempt, {
      ..exact,
      measurement: { ..exact.measurement, max_bytes: bytes, },
    })
    if bytes == 47 {
      result.unwrap() |> ignore
    } else {
      assert_true(
        result is Err(Retention(OutputIdentity(Encoding(OutputLimit)))),
      )
      assert_true(@planning.duckdb_broad_attempt_output(attempt) is None)
    }
  }
  let too_small = completed_broad_attempt()
  assert_true(
    @planning.retain_duckdb_broad_attempt(too_small, {
      ..exact,
      received_wire_bytes: 27,
      measurement: { ..exact.measurement, max_nodes: 7, },
    })
    is Err(Retention(ReceiptBytes)),
  )
}
