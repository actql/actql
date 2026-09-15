///|
fn query_retention_limits() -> @mock.MockRetentionLimits {
  {
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
}

///|
fn query_retention_attempt(
  route : @mock.QueryRealization,
) -> @mock.MockQueryAttempt raise {
  let (program, sequence) = query_program_fixture()
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    program,
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let attempt = @mock.prepare_requirement_mock_query_attempt(
    requirement,
    strategy_for(sequence, route),
    [
      input_cursor("{\"id\":3}"),
      input_cursor("{\"id\":1}"),
      input_cursor("{\"id\":2}"),
    ],
    3,
  ).unwrap()
  @mock.execute_mock_query(
    attempt,
    mock_strategy_limits(),
    guard_measure=Some(query_guard_physical()),
  ).unwrap()
  |> ignore
  attempt
}

///|
test "mock capture retention counts full scan even for native receipt" {
  let mut prior : (String, String)? = None
  for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
    let attempt = query_retention_attempt(route)
    let retained = @mock.retain_mock_query(attempt, query_retention_limits()).unwrap()
    // Independent wire lengths: scan array 28 bytes / 7 nodes; selected array
    // 19 bytes / 5 nodes. Both are retained, only receipt differs by route.
    assert_eq(
      @mock.mock_retention_usage(retained),
      (if route == @mock.NativeQuery { 19 } else { 28 }, 47, 12),
    )
    let cids = @mock.mock_retention_row_cids(retained)
    assert_eq(
      cids.0,
      "sha256:77e98e23cd26d76b7d4549460e2d627af92fbdabe8de4cb20c0106d26470d26d",
    )
    assert_eq(
      cids.1,
      "sha256:b578d4eb7cd3e1c8e66fd5758a9c5a98dc05739e4c6fa282fc372aec70930e18",
    )
    if prior is Some(expected) {
      assert_eq(cids, expected)
    }
    prior = Some(cids)
    assert_true(
      @mock.retain_mock_query(attempt, query_retention_limits())
      is Err(NotAwaitingCapture),
    )
    assert_true(@mock.cancel_mock_query(attempt))
    // Retained handles may keep data alive, but do not restore task authority.
    assert_eq(@mock.mock_retention_usage(retained).1, 47)
    assert_true(@mock.mock_query_computation(attempt) is Err(Cancelled))
    assert_true(
      @mock.retain_mock_query(attempt, query_retention_limits())
      is Err(NotAwaitingCapture),
    )
  }
}

///|
test "mock retention byte and traversal frontiers fail the owning attempt" {
  for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
    let limits = query_retention_limits()
    let receipt = if route == @mock.NativeQuery { 19 } else { 28 }
    let exact = query_retention_attempt(route)
    assert_true(
      @mock.retain_mock_query(exact, { ..limits, received_wire_bytes: receipt, })
      is Ok(_),
    )
    let short_receipt = query_retention_attempt(route)
    assert_true(
      @mock.retain_mock_query(short_receipt, {
        ..limits,
        received_wire_bytes: receipt - 1,
      })
      is Err(ReceiptBytes),
    )
    assert_true(
      @mock.mock_query_computation(short_receipt)
      is Err(Retention(ReceiptBytes)),
    )
    let short_retained = query_retention_attempt(route)
    assert_true(
      @mock.retain_mock_query(short_retained, {
        ..limits,
        retained_wire_bytes: 46,
      })
      is Err(RetainedBytes),
    )
    let short_bytes = query_retention_attempt(route)
    assert_true(
      @mock.retain_mock_query(short_bytes, {
        ..limits,
        measurement: { ..limits.measurement, max_bytes: 46, },
      })
      is Err(OutputIdentity(_)),
    )
    let short_nodes = query_retention_attempt(route)
    assert_true(
      @mock.retain_mock_query(short_nodes, {
        ..limits,
        measurement: { ..limits.measurement, max_nodes: 11, },
      })
      is Err(OutputIdentity(_)),
    )
  }
}

///|
test "exhausted retention is not invalid configuration and cannot issue evidence" {
  let (issuer, sequence) = query_issuer_fixture()
  for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
    for
      (nodes, bytes, success) in [
        (7, 47, false),
        (11, 47, false),
        (12, 47, true),
        (12, 28, false),
        (12, 46, false),
      ] {
      let attempt = query_issuer_attempt(issuer, sequence, route)
      @mock.execute_mock_query(
        attempt,
        mock_strategy_limits(),
        guard_measure=Some(query_guard_physical()),
      ).unwrap()
      |> ignore
      let result = @mock.retain_mock_query(attempt, {
        ..query_retention_limits(),
        measurement: {
          ..query_retention_limits().measurement,
          max_nodes: nodes,
          max_bytes: bytes,
        },
      })
      if success {
        assert_true(result is Ok(_))
        let records = @mock.issue_mock_query_records(
          attempt,
          query_material_limits(),
        ).unwrap()
        assert_true(
          @mock.capture_mock_query(
            issuer,
            attempt,
            records,
            query_capture_limits(),
          )
          is Ok(_),
        )
      } else {
        assert_true(
          result is Err(OutputIdentity(Encoding(@encode.OutputLimit))),
        )
        assert_true(
          @mock.mock_query_computation(attempt)
          is Err(Retention(OutputIdentity(Encoding(@encode.OutputLimit)))),
        )
        assert_true(
          @mock.issue_mock_query_records(attempt, query_material_limits())
          is Err(NotRetained),
        )
      }
    }
    let invalid = query_retention_attempt(route)
    assert_true(
      @mock.retain_mock_query(invalid, {
        ..query_retention_limits(),
        measurement: { ..query_retention_limits().measurement, max_nodes: 0, },
      })
      is Err(ScanIdentity(InvalidLimits)),
    )
  }
  let broad = query_retention_attempt(@mock.BroadWithResidual)
  assert_true(
    @mock.retain_mock_query(broad, {
      ..query_retention_limits(),
      received_wire_bytes: 27,
      measurement: { ..query_retention_limits().measurement, max_nodes: 7, },
    })
    is Err(ReceiptBytes),
  )
}

///|
test "unbound or cancelled mock computation cannot establish retention" {
  let owner = strategy_test_owner()
  let attempt = @mock.prepare_mock_query_attempt(
    strategy_for(owner, @mock.NativeQuery),
    [],
    0,
  ).unwrap()
  assert_true(
    @mock.retain_mock_query(attempt, query_retention_limits())
    is Err(NotAwaitingCapture),
  )
  @mock.execute_mock_query(attempt, mock_strategy_limits()).unwrap() |> ignore
  assert_true(
    @mock.retain_mock_query(attempt, query_retention_limits())
    is Err(RequirementRequired),
  )
  let bound = query_retention_attempt(@mock.NativeQuery)
  assert_true(@mock.cancel_mock_query(bound))
  assert_true(
    @mock.retain_mock_query(bound, query_retention_limits())
    is Err(NotAwaitingCapture),
  )
}
