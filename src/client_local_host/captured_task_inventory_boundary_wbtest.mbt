///|
fn captured_task_inventory_document(task_count : Int) -> String {
  let stages : Array[String] = [
    (
      #|{"id":"capture","inputs":{"records":{"connector":"crm/main","resource":"r"}},"steps":[{"from":"records","select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}}
    ),
    (
      #|{"id":"main","inputs":{"records":{"result":{"stage":"capture","result":"rows"}}},"steps":[{"from":"records","filter":"id > 1"},{"select":["id"],"as":"selected"},{"from":"records","select":["id"],"as":"complete"},{"from":"complete","group":{"by":[],"aggregates":{"id":{"fn":"count"}}},"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}
    ),
  ]
  let mut previous = "main"
  for index in 0..<(task_count - 5) {
    let name = "compute\{index}"
    stages.push(
      "{\"id\":\"\{name}\",\"inputs\":{\"r\":{\"result\":{\"stage\":\"\{previous}\",\"result\":\"rows\"}}},\"steps\":[{\"filter\":\"id >= 0\"},{\"select\":[\"id\"],\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"id\"]}}}",
    )
    previous = name
  }
  "{\"version\":\"actql/0.1\",\"id\":\"captured-task-inventory\",\"stages\":[" +
  stages.join(",") +
  "],\"results\":{\"answer\":{\"from\":{\"stage\":\"\{previous}\",\"result\":\"rows\"}}}}"
}

///|
// Checked Source/Compute originals only; no Native File I/O or Run grant.
test "one captured Source retains checked task inventories across thirty two" {
  for count in [31, 32, 33, 35] {
    let prepared = single_installed_prepared(
      document=captured_task_inventory_document(count),
    )
    let graph = @publication_host.prepared_client_graph(prepared)
    assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 1)
    assert_eq(@strategy.graph_captured_prefix(graph), 1)
    assert_eq(@strategy.graph_result_count(graph), 1)
    assert_eq(@strategy.graph_task_count(graph), count)
    assert_false(@strategy.graph_program_has_effects(graph))
    assert_false(@publication_host.prepared_client_uses_graph_carrier(prepared))
    assert_true(
      @publication_host.prepared_client_composed_infer_occurrences(prepared)
      .unwrap()
      .is_empty(),
    )
    assert_true(
      @publication_host.prepared_client_serialization_occurrences(prepared).is_empty(),
    )
  }
}

///|
test "captured Whole Plan beyond thirty two tasks supplies no finite Ledger grant" {
  let prepared = single_installed_prepared(
    document=captured_task_inventory_document(33),
  )
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "captured-task-boundary",
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  guard select_installed_source_input(prepared, request, 0, 0).unwrap()
    is @sourceviews.WholeInputRoute(original) else {
    fail("the checked File shape must retain its original Whole input")
  }
  let source = prepare_installed_catalog_whole_source_capacity(
    prepared,
    original,
    contracts,
    installed_row_input_policy(3, 4096, 512, 8, 3),
  ).unwrap()
  let plan = prepare_installed_managed_whole_source_plan(
    prepared,
    request,
    source,
    4096L,
    4096L,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=false,
    provider_factory=_ => [],
  ).unwrap()
  assert_true(physical_equal(plan.prepared, prepared))
  assert_true(physical_equal(plan.request, request))
  assert_eq(plan.whole_sources.length(), 1)
  assert_true(@strategy.graph_task_count(plan.graph) > 32)
  assert_eq(plan.limits.attempts, @strategy.graph_task_count(plan.graph) + 1)
  assert_eq(plan.limits.holdings, plan.limits.attempts)
  assert_true(plan.limits.retained_bytes > 0L)
  assert_true(plan.limits.execution_bytes > 0L)
  // A quote may exceed a selected facility. It must not provision or enlarge
  // that facility: the ordinary caller still admits it before construction.
  let short = @resources.create_ledger({
    ..plan.limits,
    retained_bytes: plan.limits.retained_bytes - 1L,
  }).unwrap()
  assert_true(
    @resources.reserve_capacity(
      short,
      plan.limits.retained_bytes,
      plan.limits.execution_bytes,
    )
    is Err(RetentionLimit),
  )
  assert_eq(@resources.ledger_usage(short).live_reservations, 0)
  assert_eq(@resources.ledger_usage(short).attempts, 0)
  // The shape and Plan are DATA, not a grant or a refill. Actual admission
  // still spends the same finite Ledger, and settling never refunds work.
  let ledger = @resources.create_ledger({
    ..plan.limits,
    attempts: 1,
    holdings: 1,
    retained_bytes: 1L,
    execution_bytes: 1L,
  }).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(
    @resources.reserve_attempt(ledger, 0L, 2L, 0L) is Err(RetentionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  let attempt = @resources.reserve_attempt(ledger, 0L, 1L, 1L).unwrap()
  @resources.consume_reserved_attempt(ledger, attempt).unwrap()
  @resources.settle_reservation(ledger, attempt).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_true(
    @resources.reserve_attempt(ledger, 0L, 1L, 1L) is Err(AttemptLimit),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
}
