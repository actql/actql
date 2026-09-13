///|
priv struct BroadIssuerFixture {
  issuer : @planning.DuckDBQueryIssuer
  requirement : @planning.QueryRequirement
  sequence : @query.QuerySequence
  choice : @planning.AcquisitionChoice
  prepared : @planning.PreparedAcquisition[@planning.DuckDBQueryPreparation]
  transport : Array[@planning.DuckDBBroadAttempt]
}

///|
fn broad_issuer_fixture() -> BroadIssuerFixture raise {
  let checked = query_checked_program_fixture()
  let sequence = query_checked_sequence(checked)
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(checked),
    { max_rows: 2, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let registry = @planning.prepare_capability_registry(
    [{ name: "duckdb", acquisition: true, fixed_compute: true, }],
    1,
    6,
  ).unwrap()
  let prepared = @planning.duckdb_broad_candidate(
    @planning.capability_registration_at(registry, 0).unwrap(),
    @planning.prepare_duckdb_query(
      requirement,
      "main",
      "records",
      10,
      native_compile_limits(),
    ).unwrap(),
    [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(prepared)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    abort("complete candidate")
  }
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  // Portable trusted-Host double. The Node coordinator must use exact settled
  // grant/port/read-view provenance, not this test's manually completed set.
  let transport : Array[@planning.DuckDBBroadAttempt] = []
  let issuer = @planning.prepare_duckdb_query_issuer(
    contracts,
    requirement,
    "test-process",
    100,
    attempt => transport.any(value => physical_equal(value, attempt)),
  ).unwrap()
  { issuer, requirement, sequence, choice, prepared, transport, }
}

///|
fn broad_issued_attempt(f : BroadIssuerFixture) -> @planning.DuckDBBroadAttempt {
  @planning.prepare_issued_duckdb_broad_attempt(f.issuer, f.choice, f.prepared).unwrap()
}

///|
fn broad_issued_run(
  f : BroadIssuerFixture,
  attempt : @planning.DuckDBBroadAttempt,
) -> Unit {
  broad_attempt_receive(attempt)
  @planning.settle_duckdb_broad_transport(attempt).unwrap()
  f.transport.push(attempt)
  @planning.execute_duckdb_broad_attempt(
    attempt,
    compute_test_limits(),
    query_guard_physical(),
  ).unwrap()
  @planning.retain_duckdb_broad_attempt(attempt, {
    received_wire_bytes: 28,
    retained_wire_bytes: 47,
    measurement: {
      max_columns: 10,
      max_order_work: 1000,
      max_bytes: 47,
      max_nodes: 12,
      max_depth: 10,
    },
  }).unwrap()
  |> ignore
}

///|
test "selected DuckDB broad records capture and consumer preserve the independent observation contract" {
  let f = broad_issuer_fixture()
  let attempt = broad_issued_attempt(f)
  assert_true(
    @planning.issue_duckdb_broad_records(attempt, query_material_limits())
    is Err(NotRetained),
  )
  broad_issued_run(f, attempt)
  let records = @planning.issue_duckdb_broad_records(
    attempt,
    query_material_limits(),
  ).unwrap()
  let (expected, expected_records) = query_observation_oracle(
    f.requirement,
    @planning.duckdb_broad_attempt_identity(attempt).unwrap(),
    "[{\"id\":3},{\"id\":1},{\"id\":2}]",
    3,
    "[\"id\"]",
    "[{\"id\":3},{\"id\":2}]",
    2,
  )
  for i in 0..<3 {
    let (_, cid) = @planning.duckdb_broad_record_at(records, i).unwrap()
    assert_eq(cid, expected_records[i])
  }
  let observation = @planning.capture_duckdb_broad_query(
    f.issuer,
    attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  assert_eq(
    @encode.document_text(
      @planning.duckdb_broad_observation_document(observation),
    ),
    expected,
  )
  assert_eq(
    @planning.duckdb_broad_observation_cid(observation),
    query_material_expected(expected),
  )
  @planning.abort_duckdb_broad_attempt(attempt)
  assert_true(
    @planning.verify_duckdb_broad_records(f.issuer, attempt, records) is Ok(_),
  )
  assert_true(
    @planning.capture_duckdb_broad_query(
      f.issuer,
      attempt,
      records,
      query_capture_limits(),
    )
    is Err(AlreadyCaptured),
  )
  let owner = @query.query_sequence_owner(f.sequence)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  let generated = compute_test_sequence(receiver)
  for succeeds in [false, true] {
    let input = @planning.bind_captured_duckdb_broad_input(
      f.issuer,
      attempt,
      observation,
      receiver,
      0,
      owner,
    ).unwrap()
    let run = @execution.prepare_local_compute_attempt(generated, [input], 3).unwrap()
    let limits = compute_test_limits()
    let result = @execution.execute_local_compute_attempt(
      run,
      if succeeds {
        limits
      } else {
        { ..limits, rows: { ..limits.rows, max_rows: 1, }, }
      },
    )
    if succeeds {
      let output = @execution.completed_output(result.unwrap(), Step(0)).unwrap()
      assert_eq(@execution.completed_row_count(output), 2)
      assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
      assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
    } else {
      assert_true(result is Err(_))
    }
    assert_true(
      @planning.verify_duckdb_broad_records(f.issuer, attempt, records) is Ok(_),
    )
  }
  let other = broad_issued_attempt(f)
  broad_issued_run(f, other)
  assert_true(
    @planning.verify_duckdb_broad_records(f.issuer, other, records)
    is Err(UnauthorizedAttempt),
  )
  let wrong_target = typed_receiver(
    owner,
    "[{\"select\":[\"id\"]}]",
    target=Step(0),
  )
  assert_true(
    @planning.bind_captured_duckdb_broad_input(
      f.issuer,
      attempt,
      observation,
      wrong_target,
      0,
      owner,
    )
    is Err(Consumer(ProducerTargetMismatch)),
  )
  let prepared_owner = @lower.bound_preparation(owner)
  let declarations = @pipeline.parameters(@lower.pipeline(prepared_owner)).unwrap()
  guard @parameter.bind(declarations, Some(input_cursor("{\"minimum\":2}")), {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is @parameter.Ready(values) else {
    abort("bound Parameter")
  }
  let rebound = @lower.bind_parameters(
    prepared_owner,
    Some(values),
    max_parameters=1,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    @planning.bind_captured_duckdb_broad_input(
      f.issuer,
      attempt,
      observation,
      receiver,
      0,
      rebound,
    )
    is Err(Consumer(ProducerBindingMismatch)),
  )
  f.transport.clear()
  assert_true(
    @planning.bind_captured_duckdb_broad_input(
      f.issuer,
      attempt,
      observation,
      receiver,
      0,
      owner,
    )
    is Err(UnverifiedTransport),
  )
  @planning.close_duckdb_query_issuer(f.issuer)
}

///|
test "DuckDB issuer refuses unissued unverified failed and foreign attempts" {
  let f = broad_issuer_fixture()
  let unissued = broad_attempt_fixture()
  assert_true(
    @planning.issue_duckdb_broad_records(unissued, query_material_limits())
    is Err(UnauthorizedAttempt),
  )
  let attempt = broad_issued_attempt(f)
  broad_issued_run(f, attempt)
  f.transport.clear()
  assert_true(
    @planning.issue_duckdb_broad_records(attempt, query_material_limits())
    is Err(UnverifiedTransport),
  )
  f.transport.push(attempt)
  assert_true(
    @planning.issue_duckdb_broad_records(attempt, query_material_limits())
    is Err(NotRetained),
  )
  let failed = broad_issued_attempt(f)
  broad_issued_run(f, failed)
  assert_true(
    @planning.issue_duckdb_broad_records(failed, {
      ..query_material_limits(),
      max_bytes: 0,
    })
    is Err(Encoding(_)),
  )
  assert_true(
    @planning.issue_duckdb_broad_records(failed, query_material_limits())
    is Err(NotRetained),
  )
  let foreign = broad_issuer_fixture()
  assert_true(
    @planning.prepare_issued_duckdb_broad_attempt(
      foreign.issuer,
      f.choice,
      f.prepared,
    )
    is Err(UnauthorizedAttempt),
  )
  @planning.close_duckdb_query_issuer(f.issuer)
  assert_true(
    @planning.prepare_issued_duckdb_broad_attempt(
      f.issuer,
      f.choice,
      f.prepared,
    )
    is Err(IssuerClosed),
  )
  @planning.close_duckdb_query_issuer(foreign.issuer)
  f.transport.clear()
}

///|
test "DuckDB capture keeps cumulative artifact budget equality and fails atomically" {
  let f = broad_issuer_fixture()
  let first = broad_issued_attempt(f)
  broad_issued_run(f, first)
  let records = @planning.issue_duckdb_broad_records(
    first,
    query_material_limits(),
  ).unwrap()
  let baseline = @planning.capture_duckdb_broad_query(
    f.issuer,
    first,
    records,
    query_capture_limits(),
  ).unwrap()
  let (bytes, nodes) = @planning.duckdb_broad_observation_usage(baseline)
  for short in [false, true] {
    let attempt = broad_issued_attempt(f)
    broad_issued_run(f, attempt)
    let records = @planning.issue_duckdb_broad_records(
      attempt,
      query_material_limits(),
    ).unwrap()
    let result = @planning.capture_duckdb_broad_query(
      f.issuer,
      attempt,
      records,
      {
        max_bytes: bytes - (if short { 1 } else { 0 }),
        max_nodes: nodes,
        max_depth: 100,
      },
    )
    if short {
      assert_true(result is Err(Encoding(_)))
      assert_true(
        @planning.verify_duckdb_broad_records(f.issuer, attempt, records)
        is Err(ForeignRecords),
      )
    } else {
      assert_true(result is Ok(_))
    }
  }
  @planning.close_duckdb_query_issuer(f.issuer)
  f.transport.clear()
}
