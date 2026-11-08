///|
// Actual Core Source/Task/Resource owners with public fixture rows on one
// finite diagnostic Ledger. Transport verification is an explicit fixture
// port; this is not Account, native backing or ordinary Host acceptance.
test "set expression starts its first task beside the original whole Source" {
  let prepared = set_output_expression_prepared()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "set-first-task",
  ).unwrap()
  guard select_installed_source_input(prepared, request, 0, 0).unwrap()
    is @sourceviews.WholeInputRoute(original) else {
    fail("the same set expression selects Whole Source")
  }
  let policy = installed_row_input_policy(10000, 10000000, 110101, 2, 10000)
  let source = prepare_installed_catalog_whole_source_capacity(
    prepared, original, contracts, policy,
  ).unwrap()
  let plan = prepare_installed_managed_whole_source_plan(
    prepared,
    request,
    source,
    10000000L,
    239908928L,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=false,
    provider_factory=_ => [],
    runtime_admission=true,
  ).unwrap()
  let limits = {
    ..plan.limits,
    retained_bytes: client_local_retained_byte_ceiling(),
    execution_bytes: client_local_execution_byte_ceiling(),
  }
  let ledger = @resources.create_ledger(limits).unwrap()
  let rows = @row_source_host.start_accounted_row_input_acquisition(
    source.acquisition,
    source.provider,
    "set-original-source",
    _ => true,
    ledger,
    10000000L,
    239908928L,
  ).unwrap()
  @row_source_host.begin_row_run_with_page_limits(rows, policy.page, 10000).unwrap()
  let wire = @utf8.encode(
    "[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]",
  )
  let charged = @row_source_host.charge_row_run_page(rows, wire).unwrap()
  assert_eq(
    @row_source_host.accept_charged_row_run_page(rows, charged, wire).unwrap(),
    4,
  )
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut captured = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
      captured = true
      break
    }
  }
  assert_true(captured)
  let capture = @row_source_host.capture_row_run(rows).unwrap()
  let dag = @strategy.open_source_inputs_dag(
    plan.graph,
    [@row_source_host.row_capture_source(capture).unwrap()],
    ledger,
  ).unwrap()
  @row_source_host.check_row_input_compute_binding(capture, dag, 0).unwrap()
  let host = bind_client_local_configuration(
    dag,
    plan.configuration,
    1L,
    1L,
    1L,
    1L,
  ).unwrap()
  @host_driver.refresh_compute_host(@builtin.configured_host_runtime(host)).unwrap()
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(host),
  ).unwrap()
  assert_eq(@strategy.next_captured_task(dag), Some(0))
  let dispatch = @local_driver.prepare_local_managed_dispatch_with_outputs(
      installed,
      [@local_driver.local_managed_supplied_relation_input()],
      @strategy.captured_next_managed_obligations(dag, 100000).unwrap(),
      0L,
    )
    .unwrap()
    .unwrap()
  @strategy.select_captured_managed_registration(
    dag,
    0,
    @local_driver.local_dispatch_registration(installed),
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  println(
    "set-actual-start-budget " +
    @debug.to_string(
      (
        limits.retained_bytes,
        limits.execution_bytes,
        before.held_bytes,
        before.reserved_retention_bytes,
        before.reserved_execution_bytes,
        @local_driver.local_managed_dispatch_site_capacity(dispatch).unwrap(),
      ),
    ),
  )
  let started = @local_driver.start_local_managed_dispatch_node(dispatch)
  match started {
    Err(@local_driver.Execution(Physical(issue))) =>
      println("set-actual-start-ledger-issue " + @debug.to_string(issue))
    Err(_) => println("set-actual-start-other-issue")
    Ok(_) => println("set-actual-start-accepted")
  }
  if started is Err(_) {
    @strategy.stop_captured_dag(dag)
    @row_source_host.close_accounted_row_run(rows).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    fail(
      "the bounded first task must start without preallocating unused output",
    )
  }
  let operations = started.unwrap()
  guard @execution.generated_sequence_step_at(plan.compute_sequences[0], 0)
    is Some(@lower.RowStep(first_kernel)) else {
    fail("the original first task must be a row kernel")
  }
  assert_true(@lower.kernel_body(first_kernel) is @lower.Select(_))
  (operations.execute)().unwrap()
  let output_live = Ref(true)
  (operations.prepare_finalization)(0, operations.storage_bytes, () => {
    output_live.val
  }).unwrap()
  let mut finalized = false
  for _ in 0..<10000 {
    if (operations.advance_finalization)(256).unwrap().complete {
      finalized = true
      break
    }
  }
  assert_true(finalized)
  (operations.settle)().unwrap()
  let completed = (operations.complete)(0, operations.storage_bytes, () => {
    output_live.val
  }).unwrap()
  assert_eq(@execution.managed_completed_output_row_count(completed), 4)
  let expected : Array[Json] = [
    { "amount": 30, "id": 3 },
    { "amount": Json::null(), "id": 1 },
    { "amount": 20, "id": 2 },
    { "amount": 30, "id": 3 },
  ]
  for index, row in expected {
    assert_eq(@json.parse((operations.output_row)(index).unwrap()), row)
  }
  output_live.val = false
  (operations.close)()
  let mut cleaned = false
  for _ in 0..<10000 {
    if (operations.cleanup_refresh)() {
      cleaned = true
      break
    }
  }
  assert_true(cleaned)
  @strategy.stop_captured_dag(dag)
  @row_source_host.close_accounted_row_run(rows).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.live_reservations, 0)
  assert_eq(after.held_bytes, 0L)
  assert_eq(after.reserved_execution_bytes, 0L)
}
