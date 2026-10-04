///|
fn[T] source_restart_ok(
  result : Result[T, @client_local_host.ClientSourceCaptureIssue],
) -> T raise {
  match result {
    Ok(value) => value
    Err(issue) =>
      fail(
        match issue {
          BindingMismatch => "source binding mismatch"
          InvalidDescriptor => "invalid source descriptor"
          CustodyUnavailable => "source custody unavailable"
          Content(IdentityMismatch) => "source content identity mismatch"
          Content(ForeignContract) => "source content foreign contract"
          Content(MetadataLimit) => "source content metadata limit"
          Content(_) => "source content admission failure"
          Capture(_) => "source capture port failure"
          Readmission(_) => "source retained readmission failure"
          Import(_) => "source representation import failure"
          Export(_) => "source export failure"
          Evidence(_) => "source completion evidence failure"
          Physical(_) => "source physical reservation failure"
        },
      )
  }
}

///|
fn source_restart_requirement(
  id? : String = "p",
) -> (@planning.QueryRequirement, @query.QuerySequence) raise {
  let (program, sequence) = query_program_fixture(id~)
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    program,
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  (requirement, sequence)
}

///|
fn source_restart_export(
  route : @mock.QueryRealization,
  binding : String,
) -> (@client_local_host.ClientSourceCaptureExport, @query.CapturedInputSource) raise {
  let (requirement, sequence) = source_restart_requirement()
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let issuer = @mock.prepare_mock_query_issuer(
    contracts, requirement, "source-restart-test", 100,
  ).unwrap()
  let attempt = query_issuer_attempt(issuer, sequence, route)
  query_issuer_run(attempt)
  let records = @mock.issue_mock_query_records(attempt, query_material_limits()).unwrap()
  let observation = @mock.capture_mock_query(
    issuer,
    attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  let source = @mock.mock_captured_source(issuer, attempt, observation).unwrap()
  let exported = @client_local_host.export_client_source_capture(
    source, requirement, binding,
  ).unwrap()
  @mock.close_mock_query_issuer(issuer)
  assert_false(@query.captured_source_available(source))
  (exported, source)
}

///|
test "durable source bridge restores exact Native and Broad values under fresh checked owners" {
  let binding = "run-a/task-0/input-0/attempt-1/native-or-broad/table-a/generation-1"
  for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
    let (exported, original) = source_restart_export(route, binding)
    assert_eq(@client_local_host.client_source_capture_export_rows(exported), [
      "{\"id\":3}", "{\"id\":2}",
    ])
    let (requirement, query) = source_restart_requirement()
    assert_false(@query.captured_source_matches_query(original, query))
    let owner = source_restart_ok(
      @client_local_host.restore_client_source_capture(
        requirement,
        @client_local_host.client_source_capture_export_requirement(exported),
        binding,
        @client_local_host.client_source_capture_export_binding(exported),
        @client_local_host.client_source_capture_export_descriptor(exported),
        @client_local_host.client_source_capture_export_rows(exported),
        fn() { true },
      ),
    )
    let restored = @client_local_host.client_source_capture_source(owner).unwrap()
    assert_true(@query.captured_source_matches_query(restored, query))
    let receiver = typed_receiver(
      @query.query_sequence_owner(query),
      "[{\"select\":[\"id\"]}]",
    )
    let bound = @query.bind_captured_source(restored, receiver, 0).unwrap()
    let attempt = @execution.prepare_local_compute_attempt(
      compute_test_sequence(receiver),
      [bound],
      3,
    ).unwrap()
    let completed = @execution.execute_local_compute_attempt(
      attempt,
      compute_test_limits(),
    ).unwrap()
    let output = @execution.completed_output(completed, Step(0)).unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
    assert_true(@client_local_host.close_client_source_capture(owner))
    assert_false(@client_local_host.close_client_source_capture(owner))
    assert_false(@query.captured_source_available(restored))
  }
}

///|
test "durable source bridge rejects descriptor and rows without verified custody" {
  let binding = "run-a/task-0/input-0/attempt-1/native/table-a/generation-1"
  let (exported, _) = source_restart_export(@mock.NativeQuery, binding)
  let (requirement, _) = source_restart_requirement()
  assert_true(
    @client_local_host.restore_client_source_capture(
      requirement,
      @client_local_host.client_source_capture_export_requirement(exported),
      binding,
      binding,
      @client_local_host.client_source_capture_export_descriptor(exported),
      @client_local_host.client_source_capture_export_rows(exported),
      fn() { false },
    )
    is Err(CustodyUnavailable),
  )
  assert_true(
    @client_local_host.restore_client_source_capture(
      requirement,
      @client_local_host.client_source_capture_export_requirement(exported),
      binding,
      binding,
      @client_local_host.client_source_capture_export_descriptor(exported),
      ["{\"id\":3}", "{\"id\":9}"],
      fn() { true },
    )
    is Err(Content(_)),
  )
}

///|
test "durable source bridge fences another occurrence physical binding and Program" {
  let binding = "run-a/task-0/input-0/attempt-1/native/table-a/generation-1"
  let (exported, _) = source_restart_export(@mock.NativeQuery, binding)
  let descriptor = @client_local_host.client_source_capture_export_descriptor(
    exported,
  )
  let rows = @client_local_host.client_source_capture_export_rows(exported)
  let requirement_cid = @client_local_host.client_source_capture_export_requirement(
    exported,
  )
  let (requirement, _) = source_restart_requirement()
  for
    changed in [
      "run-b/task-0/input-0/attempt-1/native/table-a/generation-1", "run-a/task-1/input-0/attempt-1/native/table-a/generation-1",
      "run-a/task-0/input-0/attempt-2/native/table-a/generation-1", "run-a/task-0/input-0/attempt-1/broad/table-a/generation-1",
      "run-a/task-0/input-0/attempt-1/native/table-b/generation-1", "run-a/task-0/input-0/attempt-1/native/table-a/generation-2",
    ] {
    assert_true(
      @client_local_host.restore_client_source_capture(
        requirement,
        requirement_cid,
        changed,
        binding,
        descriptor,
        rows,
        fn() { true },
      )
      is Err(BindingMismatch),
    )
  }
  let (foreign, _) = source_restart_requirement(id="another-program")
  assert_true(
    @client_local_host.restore_client_source_capture(
      foreign,
      requirement_cid,
      binding,
      binding,
      descriptor,
      rows,
      fn() { true },
    )
    is Err(BindingMismatch),
  )
}

///|
test "durable source bridge preserves receiving custody revocation after conversion" {
  let binding = "run-a/task-0/input-0/attempt-1/native/table-a/generation-1"
  let (exported, _) = source_restart_export(@mock.NativeQuery, binding)
  let (requirement, _) = source_restart_requirement()
  let held = Ref(true)
  let owner = source_restart_ok(
    @client_local_host.restore_client_source_capture(
      requirement,
      @client_local_host.client_source_capture_export_requirement(exported),
      binding,
      binding,
      @client_local_host.client_source_capture_export_descriptor(exported),
      @client_local_host.client_source_capture_export_rows(exported),
      fn() { held.val },
    ),
  )
  let source = @client_local_host.client_source_capture_source(owner).unwrap()
  held.val = false
  assert_true(@client_local_host.client_source_capture_source(owner) is None)
  assert_false(@query.captured_source_available(source))
  assert_true(@client_local_host.close_client_source_capture(owner))
}

///|
test "durable source bridge keeps original observation binding and charged DAG cleanup custody" {
  let binding = "run-a/task-0/input-0/attempt-1/native/table-a/generation-1"
  let (graph, _, requirement) = resident_native_source_setup(
    evidence_members=true,
  )
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let issuer = @mock.prepare_mock_query_issuer(
    contracts, requirement, "saved-source", 100,
  ).unwrap()
  let attempt = query_issuer_attempt(issuer, query, @mock.NativeQuery)
  query_issuer_run(attempt)
  let records = @mock.issue_mock_query_records(attempt, query_material_limits()).unwrap()
  let observation = @mock.capture_mock_query(
    issuer,
    attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  let source = @mock.mock_captured_source(issuer, attempt, observation).unwrap()
  let limits = native_publication_export_limits()
  let identity = @query.identify_captured_source_relation(
    source,
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
  let logical = @publication_host.issue_captured_source_input_logical(
    graph, source, identity, requirement,
  ).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let policy = "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf"
  let (source_ref, source_contract) = @planning.query_requirement_source(
    requirement,
  )
  // An independent saved observation fixture exercises the same binding
  // reader used by acquired Effect invocation publication. No new issuer is
  // consulted during restoration and its original snapshot reference survives.
  let evidence_json : Json = {
    "version": "actql-source-evidence/0.1",
    "source_ref": source_ref,
    "input_logical_cid": @publication.run_evidence_value_identity(logical),
    "source_contract_cid": source_contract,
    "schema_evidence_cid": "sha256:" + "b".repeat(64),
    "capability_evidence_cid": "sha256:" + "c".repeat(64),
    "authority_scope_cid": scope,
    "source_data_policy_cid": policy,
    "effective_data_policy_cid": policy,
    "data_classification": "unknown",
    "source_view_contract_cid": source_contract,
    "output_carrier": "relation",
    "read_mode": "snapshot",
    "observed_at": "2026-10-03T00:00:01.000Z",
    "snapshot_ref": @mock.mock_query_observation_cid(observation),
    "completeness": "complete",
    "consistency_level": "snapshot",
    "ordering_evidence": { "stable": false, "keys": [] },
  }
  let saved_evidence = @publication.seal_run_evidence_value(
    "source_evidence",
    evidence_json.stringify(),
    32768,
    256,
    16,
  ).unwrap()
  let exported = @client_local_host.export_client_source_capture(
    source, requirement, binding,
  ).unwrap()
  let original_logical_wire = @publication.run_evidence_value_json(logical)
  @mock.close_mock_query_issuer(issuer)
  let (next_graph, _, next_requirement) = resident_native_source_setup(
    evidence_members=true,
  )
  let capacity = pending_capture_capacity(next_requirement)
  let quantities = @client_local_host.client_duckdb_capture_capacity_values(
    capacity,
  )
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 1000000L,
    retained_bytes: quantities[0],
    execution_bytes: quantities[1],
  }).unwrap()
  let restored = source_restart_ok(
    @client_local_host.restore_accounted_client_source_capture(
      next_requirement,
      @client_local_host.client_source_capture_export_requirement(exported),
      binding,
      binding,
      @client_local_host.client_source_capture_export_descriptor(exported),
      @client_local_host.client_source_capture_export_rows(exported),
      ledger,
      capacity,
      fn() { true },
    ),
  )
  let captured = @client_local_host.accounted_client_source_capture_source(
    restored,
  ).unwrap()
  let restored_identity = @query.identify_captured_source_relation(
    captured,
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
  let restored_logical = @publication_host.issue_captured_source_input_logical(
    next_graph, captured, restored_identity, next_requirement,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(restored_logical),
    original_logical_wire,
  )
  assert_true(
    @publication.admit_completed_source_observation_binding(
      saved_evidence, restored_logical, source_ref, source_contract, scope, policy,
      32768, 256, 16,
    )
    is Ok(_),
  )
  assert_true(@resources.ledger_usage(ledger).held_bytes > 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  let run = @strategy.open_captured_dag(next_graph, captured, ledger).unwrap()
  assert_true(
    @client_local_host.retain_accounted_client_source_capture_task(
      restored, run, 1,
    )
    is Err(BindingMismatch),
  )
  @client_local_host.retain_accounted_client_source_capture_task(
    restored, run, 0,
  ).unwrap()
  let occurrence = @strategy.graph_result_occurrence(next_graph, 0).unwrap()
  let borrow = @strategy.borrow_captured_any_result_output(
    run, 0, occurrence, 10,
  ).unwrap()
  assert_false(
    @client_local_host.close_accounted_client_source_capture(restored),
  )
  assert_true(
    @client_local_host.accounted_client_source_capture_cleanup_pending(restored),
  )
  assert_true(@resources.ledger_usage(ledger).held_bytes > 0L)
  @strategy.release_captured_any_result_borrow(borrow) |> ignore
  assert_false(
    @client_local_host.accounted_client_source_capture_cleanup_pending(restored),
  )
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(
    @client_local_host.close_accounted_client_source_capture(restored),
  )
}
