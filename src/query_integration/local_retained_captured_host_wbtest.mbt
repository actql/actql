///|
fn retained_captured_client_preparation() -> @publication_host.PreparedClientProgram {
  let (_, _, limits) = local_effect_export_fixture()
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
    #|{"version":"actql/0.1","id":"retained-captured-client","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"out":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"r":{"result":{"stage":"acquire","result":"out"}}},"steps":[{"filter":"id >= 2","as":"kept"},{"select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"published":{"from":{"stage":"compute","result":"out"}}}}
  @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    Some(input_cursor("{\"minimum\":0}")),
    limits.program,
  ).unwrap()
}

///|
test "product captured retained factory preserves exact acquisition and bounded offers" {
  let prepared = retained_captured_client_preparation()
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
    contracts, requirement, "retained-captured-host", 100,
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
  let records = @mock.issue_mock_query_records(attempt, query_material_limits()).unwrap()
  let observation = @mock.capture_mock_query(
    issuer,
    attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  let source = @mock.mock_captured_source(issuer, attempt, observation).unwrap()
  let setup = @client_local_host.open_captured_local_retained_host(
    prepared,
    source,
    registry,
    values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=fragment,
  ).unwrap()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  assert_eq(@strategy.captured_compute_first_task(run), 1)
  assert_eq(@strategy.graph_task_count(@strategy.captured_dag_graph(run)), 2)
  // Captured Host estimates remain proposals until normal Host selection.
  assert_true(@strategy.captured_dag_strategy(run) is None)
  assert_eq(
    @local_driver.local_dispatch_rejection(
      @builtin.configured_local_module(@builtin.configured_host_modules(setup)).unwrap(),
      1,
    ),
    None,
  )
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_true(
    @client_local_host.open_captured_local_retained_host(
      retained_values_client_preparation(false),
      source,
      registry,
      values,
      1L,
      0L,
      0L,
      0L,
      fragment_body=fragment,
    )
    is None,
  )
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.attempts, 0)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  // Compute shutdown must not close the caller's acquisition owner.
  assert_true(@mock.mock_captured_source(issuer, attempt, observation) is Ok(_))
  @mock.close_mock_query_issuer(issuer)
  assert_true(
    @client_local_host.open_captured_local_retained_host(
      prepared,
      source,
      registry,
      values,
      1L,
      0L,
      0L,
      0L,
      fragment_body=fragment,
    )
    is None,
  )
}
