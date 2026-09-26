///|
fn run_local_managed_append_case(
  variant : String,
  expected : Array[String],
) -> Unit raise {
  let ledger_limits : @resources.LedgerLimits = {
    planning_work: 10000,
    attempts: 20,
    holdings: 20,
    transfer_bytes: 300000L,
    retained_bytes: 134217728L,
    execution_bytes: 536870912L,
  }
  let (run, issuer) = captured_graph_fixture(
    local_values_append_chain=true,
    local_values_append_variant=variant,
    ledger_limits=Some(ledger_limits),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()

  let producer_ops : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
  let producer_outputs : Array[@execution.ManagedCompletedOutput[Int]] = []
  let producer_lives : Array[Ref[Bool]] = []
  assert_eq(@strategy.captured_task_join_output_count(run, 3), Some(0))
  for task in [1, 2] {
    let live = Ref(true)
    let (ops, output) = run_local_managed_test_task(
      installed,
      run,
      task,
      [],
      [],
      task,
      live,
      require_provider=true,
    )
    producer_ops.push(ops)
    producer_outputs.push(output)
    producer_lives.push(live)
  }
  let append_task = 3
  let consumer_a = 4
  let consumer_b = 5
  let append_inputs = if variant == "self" {
    [producer_outputs[0], producer_outputs[0]]
  } else {
    producer_outputs
  }
  let append_rows = if variant == "self" {
    [
      local_managed_test_rows(producer_ops[0]),
      local_managed_test_rows(producer_ops[0]),
    ]
  } else {
    producer_ops.map(local_managed_test_rows)
  }
  let append_live = Ref(true)
  let (append_ops, appended) = run_local_managed_test_task(
    installed,
    run,
    append_task,
    append_inputs,
    append_rows,
    append_task,
    append_live,
    require_provider=true,
    execution_quantum=1,
  )
  let rows = local_managed_test_rows(append_ops)
  assert_eq(rows, expected)

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    consumer_a,
    [appended],
    [rows],
    consumer_a,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    consumer_b,
    [appended],
    [rows],
    consumer_b,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), rows)
  assert_eq(local_managed_test_rows(second_ops), rows)

  first_live.val = false
  @strategy.close_captured_task_output(run, consumer_a)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(appended))

  second_live.val = false
  @strategy.close_captured_task_output(run, consumer_b)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  append_live.val = false
  @strategy.close_captured_task_output(run, append_task)
  (append_ops.close)()
  (append_ops.cleanup_refresh)() |> ignore
  for index, ops in producer_ops {
    producer_lives[index].val = false
    @strategy.close_captured_task_output(run, index + 1)
    (ops.close)()
    (ops.cleanup_refresh)() |> ignore
  }
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "Local managed append joins distinct local producers" {
  run_local_managed_append_case("local", ["{\"id\":1}", "{\"id\":2}"])
}

///|
test "Local managed append retains both self occurrences" {
  run_local_managed_append_case("self", ["{\"id\":1}", "{\"id\":1}"])
}

///|
test "Local managed append handles an empty left side" {
  run_local_managed_append_case("empty_left", ["{\"id\":2}"])
}

///|
test "Local managed append handles an empty right side" {
  run_local_managed_append_case("empty_right", ["{\"id\":1}"])
}

///|
test "Local managed append handles two empty sides" {
  run_local_managed_append_case("empty_both", [])
}

///|
test "Local managed append aligns fields in authored left order" {
  run_local_managed_append_case("aligned", [
    "{\"id\":1,\"tag\":\"left\"}", "{\"id\":2,\"tag\":\"right\"}",
  ])
}

///|
test "Local managed append consumes two imported producers" {
  run_local_managed_append_case("imported", [
    "{\"id\":1}", "{\"id\":2}", "{\"id\":3}",
  ])
}

///|
test "Local bounded append filter chain retains two consumers" {
  run_local_managed_append_case("imported_filter", ["{\"id\":2}", "{\"id\":3}"])
}

///|
test "ordinary append filter chain reserves both live children" {
  let (run, issuer) = captured_graph_fixture(
    local_values_append_chain=true,
    local_values_append_variant="imported_filter",
  )
  let sequence = dispatch_test_generated(run)[2]
  assert_eq(@execution.generated_sequence_step_count(sequence), 2)
  let limits = dispatch_test_limits()
  let registry = search_registry()
  let installed = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [sequence],
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    1,
  ).unwrap()
  let provider = @local_connector.local_module_managed_provider(
    installed, sequence,
  ).unwrap()
  let capacity = @local_connector.managed_provider_capacity(provider, sequence).unwrap()
  let base = @execution.generated_sequence_capacity(
    sequence,
    limits.local_execution,
    limits.guards,
  ).unwrap()
  let mut children = 0L
  for index in 0..<2 {
    let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = @execution.generated_sequence_capacity(
      selected,
      limits.local_execution,
      limits.guards,
    ).unwrap()
    children += child.retained_bytes + child.execution_bytes
  }
  // Both private completions coexist until reverse-order chain cleanup.
  // Each live child also owns the existing 256-byte handle allowance.
  assert_true(children > base.execution_bytes)
  assert_eq(capacity.retained_bytes, base.retained_bytes)
  assert_eq(capacity.execution_bytes, children + 512L)
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
}

///|
fn cancel_local_managed_append_case(variant : String) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_append_chain=true,
    local_values_append_variant=variant,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 134217728L,
      execution_bytes: 536870912L,
    }),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  let left_live = Ref(true)
  let (left_ops, left) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    left_live,
  )
  let right_live = Ref(true)
  let (right_ops, right) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    right_live,
  )
  let operations = start_local_managed_test_task_operations(
    installed,
    run,
    3,
    [left, right],
    [local_managed_test_rows(left_ops), local_managed_test_rows(right_ops)],
  )
  let mut row_seen = false
  let mut polls = 0
  while !row_seen && polls < 100 {
    polls += 1
    let observation = (operations.advance)(1).unwrap()
    assert_false(observation.complete)
    assert_true(observation.work <= 1L)
    row_seen = observation.progress > 0L
  }
  assert_true(row_seen)
  assert_true((operations.request_cancel)())
  assert_true((operations.advance)(1) is Err(_))
  assert_true((operations.execution_stopped)())
  assert_true((operations.output_row)(0) is Err(_))
  assert_true(
    (operations.complete)(3, operations.storage_bytes, fn() { true }) is Err(_),
  )
  (operations.settle)().unwrap()
  assert_true((operations.cleanup_refresh)())
  assert_false(@strategy.captured_task_completed(run, 3))
  assert_true(@execution.managed_completed_output_available(left))
  assert_true(@execution.managed_completed_output_available(right))
  left_live.val = false
  right_live.val = false
  @strategy.close_captured_task_output(run, 1)
  @strategy.close_captured_task_output(run, 2)
  (left_ops.close)()
  (right_ops.close)()
  (left_ops.cleanup_refresh)() |> ignore
  (right_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.close_captured_task_output(run, 3)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "standard Host stops external append after row work" {
  cancel_local_managed_append_case("imported")
}

///|
test "standard Host stops append filter chain without releasing its inputs" {
  cancel_local_managed_append_case("imported_filter")
}
