///|
fn query_capture_limits() -> @planning.QueryEvidenceLimits {
  { max_bytes: 100000, max_nodes: 10000, max_depth: 100, }
}

///|
test "native and residual captures feed the ordinary completed-input consumer" {
  let (issuer, sequence) = query_issuer_fixture()
  let owner = @query.query_sequence_owner(sequence)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let generated = compute_test_sequence(receiver)
  let mut prior : String? = None
  for route in [@planning.NativeQuery, @planning.BroadWithResidual] {
    // Reverse costs for the same canonical requirement; both concrete routes
    // must traverse comparison, dispatch, capture and receiving admission.
    let offers = [
      strategy_offer(
        sequence,
        @planning.NativeQuery,
        Array::make(
          6,
          Some(if route == @planning.NativeQuery { 1L } else { 10L }),
        ),
      ),
      strategy_offer(
        sequence,
        @planning.BroadWithResidual,
        Array::make(
          7,
          Some(if route == @planning.BroadWithResidual { 1L } else { 10L }),
        ),
      ),
    ]
    guard @planning.choose_query_strategy(sequence, offers, None, 4).unwrap()
      is @planning.Proposed(strategy) else {
      abort("complete cost fixture")
    }
    assert_eq(
      @planning.query_offer_realization(
        @planning.query_strategy_offer(strategy),
      ),
      route,
    )
    let attempt = @planning.prepare_issued_mock_query_attempt(
      issuer,
      strategy,
      [
        input_cursor("{\"id\":3}"),
        input_cursor("{\"id\":1}"),
        input_cursor("{\"id\":2}"),
      ],
      3,
    ).unwrap()
    query_issuer_run(attempt)
    let records = @planning.issue_mock_query_records(
      attempt,
      query_material_limits(),
    ).unwrap()
    let observation = @planning.capture_mock_query(
      issuer,
      attempt,
      records,
      query_capture_limits(),
    ).unwrap()
    assert_false(@planning.cancel_mock_query(attempt))
    assert_true(
      @planning.capture_mock_query(
        issuer,
        attempt,
        records,
        query_capture_limits(),
      )
      is Err(AlreadyCaptured),
    )
    let cid = @planning.mock_query_observation_cid(observation)
    if prior is Some(previous) {
      assert_true(previous != cid)
    }
    prior = Some(cid)
    let text = @encode.document_text(
      @planning.mock_query_observation_document(observation),
    )
    assert_eq(query_material_expected(text), cid)
    assert_true(text.contains("\"version\":\"actql-query-observation/0.1\""))
    assert_true(text.contains("\"retention\":\"process\""))
    assert_true(text.contains("\"input\":\"remote\""))
    assert_true(text.contains("\"stage\":\"a\""))
    assert_true(text.contains("\"complete\":true"))
    for
      (index, field) in [
        (0, "source_validation_evidence_cid"),
        (1, "filter_evidence_cid"),
        (2, "select_evidence_cid"),
      ] {
      let (_, record) = @planning.mock_query_record_at(records, index).unwrap()
      assert_true(text.contains("\"" + field + "\":\"" + record + "\""))
    }
    let bound = @planning.bind_captured_query_input(
      issuer, attempt, observation, receiver, 0, owner,
    ).unwrap()
    let failure = @execution.prepare_local_compute_attempt(
      generated,
      [bound],
      3,
    ).unwrap()
    let limits = compute_test_limits()
    assert_true(
      @execution.execute_local_compute_attempt(failure, {
        ..limits,
        rows: { ..limits.rows, max_rows: 1, },
      })
      is Err(Execution(_)),
    )
    assert_true(@execution.local_compute_result(failure) is Err(Execution(_)))
    // A consumer failure does not invalidate the completed observation or cause
    // a replacement read. Rebind and run with a fresh receiving budget.
    let again = @planning.bind_captured_query_input(
      issuer, attempt, observation, receiver, 0, owner,
    ).unwrap()
    let success = @execution.prepare_local_compute_attempt(
      generated,
      [again],
      3,
    ).unwrap()
    let result = @execution.execute_local_compute_attempt(success, limits).unwrap()
    let output = @execution.completed_output(result, Step(0)).unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
    assert_eq(@planning.mock_query_observation_cid(observation), cid)
  }
}

///|
test "capture binds exact attempt target and Parameter owner before consumer admission" {
  let (issuer, sequence) = query_issuer_fixture()
  let owner = @query.query_sequence_owner(sequence)
  let first = query_issuer_attempt(issuer, sequence, @planning.NativeQuery)
  let second = query_issuer_attempt(issuer, sequence, @planning.NativeQuery)
  query_issuer_run(first)
  query_issuer_run(second)
  let records = @planning.issue_mock_query_records(
    first,
    query_material_limits(),
  ).unwrap()
  let other_records = @planning.issue_mock_query_records(
    second,
    query_material_limits(),
  ).unwrap()
  assert_true(
    @planning.capture_mock_query(
      issuer,
      second,
      records,
      query_capture_limits(),
    )
    is Err(UnauthorizedAttempt),
  )
  let observed = @planning.capture_mock_query(
    issuer,
    first,
    records,
    query_capture_limits(),
  ).unwrap()
  let other = @planning.capture_mock_query(
    issuer,
    second,
    other_records,
    query_capture_limits(),
  ).unwrap()
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  assert_true(
    @planning.bind_captured_query_input(
      issuer, first, other, receiver, 0, owner,
    )
    is Err(UnauthorizedAttempt),
  )
  let wrong_target = typed_receiver(
    owner,
    "[{\"select\":[\"id\"]}]",
    target=Step(0),
  )
  assert_true(
    @planning.bind_captured_query_input(
      issuer, first, observed, wrong_target, 0, owner,
    )
    is Err(Consumer(ProducerTargetMismatch)),
  )
  let (_, foreign_sequence) = query_program_fixture(supplied="{\"minimum\":2}")
  let foreign_owner = @query.query_sequence_owner(foreign_sequence)
  assert_true(
    @planning.bind_captured_query_input(
      issuer, first, observed, receiver, 0, foreign_owner,
    )
    is Err(Consumer(ProducerOwnerMismatch)),
  )
  let prepared = @lower.bound_preparation(owner)
  let declarations = @pipeline.parameters(@lower.pipeline(prepared)).unwrap()
  guard @parameter.bind(declarations, Some(input_cursor("{\"minimum\":2}")), {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is @parameter.Ready(values) else {
    abort("bound parameter fixture")
  }
  let rebound = @lower.bind_parameters(
    prepared,
    Some(values),
    max_parameters=1,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    @planning.bind_captured_query_input(
      issuer, first, observed, receiver, 0, rebound,
    )
    is Err(Consumer(ProducerBindingMismatch)),
  )
  @planning.close_mock_query_issuer(issuer)
  assert_true(
    @planning.bind_captured_query_input(
      issuer, first, observed, receiver, 0, owner,
    )
    is Err(IssuerClosed),
  )
}

///|
test "capture shares artifact budget with records and never publishes partial success" {
  let (issuer, sequence) = query_issuer_fixture()
  let baseline = query_issuer_attempt(issuer, sequence, @planning.NativeQuery)
  query_issuer_run(baseline)
  let records = @planning.issue_mock_query_records(
    baseline,
    query_material_limits(),
  ).unwrap()
  let observation = @planning.capture_mock_query(
    issuer,
    baseline,
    records,
    query_capture_limits(),
  ).unwrap()
  let (bytes, nodes) = @planning.mock_query_observation_usage(observation)
  assert_true(bytes > @planning.mock_query_record_usage(records).0)
  for short in [false, true] {
    let attempt = query_issuer_attempt(issuer, sequence, @planning.NativeQuery)
    query_issuer_run(attempt)
    let issued = @planning.issue_mock_query_records(
      attempt,
      query_material_limits(),
    ).unwrap()
    let result = @planning.capture_mock_query(issuer, attempt, issued, {
      max_bytes: bytes - (if short { 1 } else { 0 }),
      max_nodes: nodes,
      max_depth: 100,
    })
    if short {
      assert_true(result is Err(Encoding(_)))
      assert_true(
        @planning.mock_query_computation(attempt) is Err(Evidence(Encoding(_))),
      )
      assert_true(
        @planning.verify_mock_query_records(issuer, attempt, issued)
        is Err(ForeignRecords),
      )
    } else {
      assert_true(result is Ok(_))
    }
  }
}
