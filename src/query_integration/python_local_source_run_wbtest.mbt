///|
// Independent existing Catalog/row fixtures exercise the Core boundary only.
// Actual Python/Wasm/DuckDB public execution remains a separate acceptance.
test "Local captured Run keeps its original pre-Source start and checked producer" {
  let environment = @program_check.checking_environment(
    @environment.member_environment(
      @environment.source_request_member(
        @environment.source_request_at(query_amount_nullable_catalog(), 0).unwrap(),
      ),
    ),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let document =
    #|{"version":"actql/0.1","id":"python-local-captured-run","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"out":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"r":{"result":{"stage":"acquire","result":"out"}}},"steps":[{"derive":{"value":"id + 1"},"as":"derived"},{"select":["value"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"compute","result":"out"}}}}
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
  let host = @local_run.configure_captured_source_local_compute(
    plan,
    source,
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
  assert_true(@strategy.captured_task_activation_required(run))
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
  (operations.complete)(1, operations.storage_bytes, () => available.val).unwrap()
  |> ignore
  assert_eq((operations.output_rows)(), 1)
  assert_eq((operations.output_row)(0).unwrap(), "{\"value\":4}")
  assert_eq(
    @publication_host.client_task_compilation_result_names(
      @local_run.local_run_compilation(plan),
    ),
    ["answer"],
  )
  available.val = false
  (operations.close)()
  @strategy.close_captured_task_output(run, 1)
  assert_true((operations.cleanup_refresh)())
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes,
    0L,
  )
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
