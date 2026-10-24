///|
// Independent existing Catalog/row fixtures exercise the Core boundary only.
// Actual Python/Wasm/DuckDB public execution remains a separate acceptance.
test "Local captured Run keeps its original pre-Source start and checked producer" {
  let wire_environment = @environment.member_environment(
    @environment.source_request_member(
      @environment.source_request_at(query_amount_nullable_catalog(), 0).unwrap(),
    ),
  )
  let environment = @program_check.checking_environment(
    wire_environment,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let document =
    #|{"version":"actql/0.1","id":"python-local-captured-run","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"out":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"r":{"result":{"stage":"acquire","result":"out"}}},"steps":[{"derive":{"value":"id + 1"},"as":"derived"},{"select":["value"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}}},{"id":"final","inputs":{"r":{"result":{"stage":"compute","result":"out"}}},"steps":[{"derive":{"next":"value + 1"},"as":"derived"},{"select":["next"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["next"]}}}],"results":{"answer":{"from":{"stage":"final","result":"out"}}}}
  let input = @local_input.prepare_local_input_material(
    Program(document),
    environment,
    Some(input_cursor("{\"minimum\":2}")),
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let prepared = @local_input.local_prepared_program(input)
  let account = @authorization.admit_account_configuration({
    account_id: "local-source-account",
    entries: [
      {
        entry_id: "local-source-run",
        outcome: Allow,
        scope: {
          principal: All,
          connection: All,
          resource: All,
          operation: All,
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
  let tuple : @authorization.AccessTuple = {
    principal: "local-user",
    connection: "python.local",
    resource: "runs",
    operation: "submit",
  }
  let context = "sha256:" + "a".repeat(64)
  let permit = @authorization.bind_dispatch_authorization(
    account,
    tuple,
    Activation,
    @publication_host.prepared_client_identity(prepared).program_definition_cid,
    context,
  ).unwrap()
  let plan = @local_run.prepare_captured_source_local_run(
    input,
    "sha256:" + "b".repeat(64),
    "original-source-submission",
    permit,
    account,
    tuple,
    context,
    "sha256:" + "c".repeat(64),
    "local",
    "original-source-run",
    "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @local_run.local_run_request(plan)
  let definition = @local_run.local_run_definition_cid(plan)
  let writer = @encode.writer(1000000, 100000, 64)
  @environment.emit(wire_environment, writer)
  let saved = @local_run.export_local_run_materials(
    plan,
    environment,
    @encode.finish(writer),
    Some("{\"minimum\":2}"),
  ).unwrap()
  let decoded = @local_run.restore_local_run_materials(saved, definition).unwrap()
  let restored = @local_run.restore_captured_source_local_run_from_materials(
    input,
    decoded,
    definition,
    request,
    "sha256:" + "b".repeat(64),
    permit,
    account,
    tuple,
    context,
    "sha256:" + "c".repeat(64),
  ).unwrap()
  assert_eq(@local_run.local_run_definition_cid(restored), definition)
  assert_eq(
    @publication_host.client_request_identity_relation(
      @local_run.local_run_request(restored),
      request,
    ),
    @publication_host.SameRequest,
  )
  // Fresh authored provenance cannot replace the codec-retained execution
  // Owner, even when the checked identities are equivalent.
  assert_true(
    !physical_equal(@local_run.local_run_prepared(restored), prepared),
  )
  assert_true(
    @publication_host.bind_client_task_run(
      prepared,
      @local_run.local_run_compilation(restored),
      @local_run.local_run_admission(restored),
      decoded.run_definition,
    )
    is Err(@publication_host.ForeignRun),
  )
  assert_true(
    @local_run.restore_source_free_local_run_from_materials(
      input,
      decoded,
      definition,
      request,
      "sha256:" + "b".repeat(64),
      permit,
      account,
      tuple,
      context,
      "sha256:" + "c".repeat(64),
    )
    is Err(UnsupportedCapability),
  )
  for
    (retained_definition, authority, policy) in [
      (
        "sha256:" + "f".repeat(64),
        "sha256:" + "b".repeat(64),
        "sha256:" + "c".repeat(64),
      ),
      (definition, "sha256:" + "e".repeat(64), "sha256:" + "c".repeat(64)),
      (definition, "sha256:" + "b".repeat(64), "sha256:" + "d".repeat(64)),
    ] {
    assert_true(
      @local_run.restore_captured_source_local_run_from_materials(
        input, decoded, retained_definition, request, authority, permit, account,
        tuple, context, policy,
      )
      is Err(_),
    )
  }
  // These are fixed Owner facts, not a physical durable journal receipt.
  // Obtain the common start decision before the acquisition fixture executes.
  let start = @local_run.confirm_local_run_physical_start(
    plan, request, definition, true, true, false, false, permit, account, tuple,
    context,
  ).unwrap()
  assert_true(
    @local_run.confirm_local_run_physical_start(
      plan, request, definition, true, false, false, false, permit, account, tuple,
      context,
    )
    is Err(_),
  )
  assert_true(
    @local_run.prepare_source_free_local_run(
      input,
      "sha256:" + "b".repeat(64),
      "original-source-submission",
      permit,
      account,
      tuple,
      context,
      "sha256:" + "c".repeat(64),
      "local",
      "original-source-run",
      "2026-10-10T00:00:00.000Z",
      "2099-01-01T00:00:00.000Z",
    )
    is Err(UnsupportedCapability),
  )
  let registry = @identity.stringify_value(
    registered_body(),
    100000,
    10000,
    100,
  )
  let values = @identity.stringify_value(
    registered_values(),
    100000,
    10000,
    100,
  )
  let fragment = Some(
    @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
  )
  let registry = @client_local_host.prepare_installed_sequence_contracts(
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let requirement = @client_local_host.prepare_local_query_requirement(
    prepared,
    0,
    0,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let issuer = @mock.prepare_mock_query_issuer(
    contracts, requirement, "python-local-source-physical-fixture", 100,
  ).unwrap()
  let attempt = query_issuer_attempt(
    issuer,
    sequence,
    @mock.NativeQuery,
    rows=Some([
      "{\"id\":3,\"amount\":null}", "{\"id\":1,\"amount\":null}", "{\"id\":2,\"amount\":null}",
    ]),
  )
  query_issuer_run(attempt, retention={
    received_wire_bytes: 1000,
    retained_wire_bytes: 2000,
    measurement: {
      max_columns: 10,
      max_order_work: 1000,
      max_bytes: 2000,
      max_nodes: 100,
      max_depth: 10,
    },
  })
  let observation = @mock.capture_mock_query(
    issuer,
    attempt,
    @mock.issue_mock_query_records(attempt, query_material_limits()).unwrap(),
    query_capture_limits(),
  ).unwrap()
  let source = @mock.mock_captured_source(issuer, attempt, observation).unwrap()
  let root = @resources.create_ledger({
    planning_work: 100000,
    attempts: 32,
    holdings: 32,
    transfer_bytes: 32000000L,
    retained_bytes: 200000000L,
    execution_bytes: 536870912L,
  }).unwrap()
  // An independent Host workspace stays reserved while this same root runs
  // and later releases Compute. This is a fixed reservation, not RSS evidence.
  let physical_stopped = Ref(false)
  let physical_cleaned = Ref(false)
  let workspace = @buffers.reserve_workspace(
    root,
    128L,
    () => physical_stopped.val,
    () => physical_cleaned.val,
  ).unwrap()
  let host = @local_run.configure_captured_source_local_compute_on_ledger(
    plan,
    source,
    root,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  assert_true(
    @local_run.configure_captured_source_local_compute(
      plan,
      @query.restrict_captured_source(source, () => false),
      registry,
      values,
      fragment,
      None,
    )
    is Err(_),
  )
  let other_plan = @local_run.prepare_captured_source_local_run(
    input,
    "sha256:" + "b".repeat(64),
    "different-source-submission",
    permit,
    account,
    tuple,
    context,
    "sha256:" + "c".repeat(64),
    "local",
    "different-source-run",
    "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let other_start = @local_run.confirm_local_run_physical_start(
    other_plan,
    @local_run.local_run_request(other_plan),
    @local_run.local_run_definition_cid(other_plan),
    true,
    true,
    false,
    false,
    permit,
    account,
    tuple,
    context,
  ).unwrap()
  assert_true(@local_run.bind_local_compute_start(host, other_start) is Err(_))
  let compute_start = @local_run.bind_local_compute_start(host, start).unwrap()
  let run = @local_run.local_compute_run(host)
  assert_true(physical_equal(@strategy.captured_dag_ledger(run), root))
  assert_true(@strategy.captured_task_activation_required(run))
  assert_true(@strategy.captured_task_retirement_pending(run))
  let operations = @local_run.start_local_compute_task(
      host,
      compute_start,
      [],
      permit,
      account,
      tuple,
      context,
    )
    .unwrap()
    .unwrap()
  let projection = @client_local_host.export_client_source_capture(
    source, requirement, definition,
  ).unwrap()
  let restored_requirement = @client_local_host.prepare_local_query_requirement(
    @local_run.local_run_prepared(restored),
    0,
    0,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let saved_rows = @client_local_host.client_source_capture_export_rows(
    projection,
  )
  let saved_descriptor = @client_local_host.client_source_capture_export_descriptor(
    projection,
  )
  let saved_binding = @client_local_host.client_source_capture_export_binding(
    projection,
  )
  let saved_requirement = @client_local_host.client_source_capture_export_requirement(
    projection,
  )
  let receiving_custody = Ref(true)
  let restored_capture = @client_local_host.restore_client_source_capture(
    restored_requirement,
    saved_requirement,
    definition,
    saved_binding,
    saved_descriptor,
    saved_rows,
    () => receiving_custody.val,
  ).unwrap()
  let restored_source = @client_local_host.client_source_capture_source(
    restored_capture,
  ).unwrap()
  assert_true(!physical_equal(restored_source, source))
  let receiving_host = @local_run.configure_captured_source_local_compute(
    restored,
    restored_source,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  assert_true(
    @client_local_host.restore_client_source_capture(
      restored_requirement,
      saved_requirement,
      @local_run.local_run_definition_cid(other_plan),
      saved_binding,
      saved_descriptor,
      saved_rows,
      () => true,
    )
    is Err(BindingMismatch),
  )
  // Closing or revoking the receiving custody does not acquire the original
  // capture's lifetime, and never initiates a replacement acquisition.
  receiving_custody.val = false
  assert_true(
    @client_local_host.client_source_capture_source(restored_capture) is None,
  )
  assert_true(@query.captured_source_available(source))
  assert_true(@client_local_host.close_client_source_capture(restored_capture))
  assert_true(!@client_local_host.close_client_source_capture(restored_capture))
  let receiving_run = @local_run.local_compute_run(receiving_host)
  @strategy.stop_captured_dag(receiving_run)
  @strategy.refresh_captured_retention(receiving_run)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(receiving_run)).reserved_execution_bytes,
    0L,
  )
  // The exact captured Source is already a Core-bound ordinary read. Its
  // absence from managed transfers must not be treated as a missing input.
  assert_eq(operations.inputs.length(), 0)
  for transfer in operations.inputs {
    for row in @client_local_host.client_source_capture_export_rows(projection) {
      (transfer.append)(row).unwrap()
    }
    (transfer.finish)().unwrap()
  }
  let mut executed = false
  for _ in 0..<1000 {
    let progress = (operations.advance)(1).unwrap()
    if progress.complete {
      executed = true
      break
    }
  }
  assert_true(executed)
  let available = Ref(true)
  (operations.prepare_finalization)(1, operations.storage_bytes, () => {
    available.val
  }).unwrap()
  let mut finalized = false
  for _ in 0..<1000 {
    let progress = (operations.advance_finalization)(1).unwrap()
    if progress.complete {
      finalized = true
      break
    }
  }
  assert_true(finalized)
  (operations.settle)().unwrap()
  let first_output = (operations.complete)(1, operations.storage_bytes, () => {
    available.val
  }).unwrap()
  assert_eq((operations.output_rows)(), 1)
  assert_eq((operations.output_row)(0).unwrap(), "{\"value\":4}")
  assert_eq(
    @publication_host.client_task_compilation_result_names(
      @local_run.local_run_compilation(plan),
    ),
    ["answer"],
  )
  let second = @local_run.start_local_compute_task(
      host,
      compute_start,
      [first_output],
      permit,
      account,
      tuple,
      context,
    )
    .unwrap()
    .unwrap()
  for transfer in second.inputs {
    (transfer.append)((operations.output_row)(0).unwrap()).unwrap()
    (transfer.finish)().unwrap()
  }
  let mut second_executed = false
  for _ in 0..<1000 {
    if (second.advance)(1).unwrap().complete {
      second_executed = true
      break
    }
  }
  assert_true(second_executed)
  let second_available = Ref(true)
  (second.prepare_finalization)(2, second.storage_bytes, () => {
    second_available.val
  }).unwrap()
  let mut second_finalized = false
  for _ in 0..<1000 {
    if (second.advance_finalization)(1).unwrap().complete {
      second_finalized = true
      break
    }
  }
  assert_true(second_finalized)
  (second.settle)().unwrap()
  let second_output = (second.complete)(2, second.storage_bytes, () => {
    second_available.val
  }).unwrap()
  assert_eq((second.output_rows)(), 1)
  assert_eq((second.output_row)(0).unwrap(), "{\"next\":5}")
  // Named Result selection uses its checked occurrence, not the last task's
  // raw rows or another producer with an equivalent schema.
  let value_limits : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 20,
    max_work: 10000,
  }
  let bridge = @execution.prepare_managed_publication_bridge(
    second_output,
    (second.material)().unwrap(),
    100,
    value_limits,
    100,
    10000,
  ).unwrap()
  @execution.append_managed_publication_bridge_wire(
    bridge,
    (second.output_row)(0).unwrap(),
    { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
  ).unwrap()
  let result_output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let result_limits : @publication_host.PublicationOutputExportLimits = {
    max_result_fields: 10,
    max_result_mapping_work: 100,
    max_result_order_work: 100,
    max_result_workspace_entries: 100,
    max_rows: 100,
    values: value_limits,
    payload_wire: row_wire_limits(),
    logical_wire: row_wire_limits(),
    schema: {
      max_fields: 10,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    },
    max_batch_bytes: 16,
  }
  assert_true(
    @publication_host.start_captured_managed_result_publication_export(
      run, 0, first_output, bridge, result_output, result_limits,
    )
    is Err(ForeignSelection),
  )
  let result_preparation = @publication_host.start_captured_managed_result_publication_export(
    run,
    0,
    second_output,
    bridge,
    result_output,
    result_limits,
    max_pins=1,
  ).unwrap()
  let mut result_ready = false
  for _ in 0..<1000 {
    let (done, work) = result_preparation.advance(1).unwrap()
    assert_true(work <= 1)
    if done {
      result_ready = true
      break
    }
  }
  assert_true(result_ready)
  let exported_result = result_preparation.finish().unwrap()
  result_preparation.cancel()
  assert_true(result_preparation.finish() is Err(InvalidState))
  let result_rows = StringBuilder()
  while exported_result.next().unwrap() is Some(chunk) {
    result_rows.write_string(chunk)
  }
  result_rows.write_string(exported_result.finish().unwrap())
  assert_eq(result_rows.to_string(), "[{\"next\":5}]")
  assert_eq(exported_result.result_fields().unwrap(), ["next"])
  assert_eq(exported_result.row_count().unwrap(), 1)
  exported_result.cancel()
  @execution.close_managed_publication_bridge(bridge)
  second_available.val = false
  (second.close)()
  @strategy.close_captured_task_output(run, 2)
  assert_true((second.cleanup_refresh)())
  available.val = false
  (operations.close)()
  @strategy.close_captured_task_output(run, 1)
  assert_true((operations.cleanup_refresh)())
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_true(@strategy.captured_task_retirement_pending(run))
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  assert_true(!@strategy.captured_task_retirement_pending(run))
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
    128L,
  )
  assert_eq(@buffers.close_workspace(workspace), Err(@buffers.CleanupPending))
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 128L)
  physical_stopped.val = true
  assert_eq(@buffers.close_workspace(workspace), Err(@buffers.CleanupPending))
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 128L)
  physical_cleaned.val = true
  @buffers.close_workspace(workspace).unwrap()
  assert_eq(@resources.ledger_usage(root).reserved_execution_bytes, 0L)
  assert_true(@mock.mock_captured_source(issuer, attempt, observation) is Ok(_))
  @mock.close_mock_query_issuer(issuer)
  assert_true(
    @local_run.configure_captured_source_local_compute(
      plan,
      source,
      registry,
      values,
      fragment,
      None,
    )
    is Err(_),
  )
}
