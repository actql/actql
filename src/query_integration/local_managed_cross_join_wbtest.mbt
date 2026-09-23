///|
fn run_local_managed_cross_join(singleton : Bool) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_cross_chain=true,
    local_values_cross_singleton=singleton,
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
  let producer_live = Ref(true)
  let (producer_ops, producer) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    producer_live,
  )
  let rows = local_managed_test_rows(producer_ops)
  assert_eq(
    rows,
    if singleton {
      ["{\"id\":1,\"tag\":\"a\"}", "{\"id\":2,\"tag\":\"a\"}"]
    } else {
      [
        "{\"id\":1,\"tag\":\"a\"}", "{\"id\":1,\"tag\":\"b\"}", "{\"id\":2,\"tag\":\"a\"}",
        "{\"id\":2,\"tag\":\"b\"}",
      ]
    },
  )
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    2,
    [producer],
    [rows],
    2,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    3,
    [producer],
    [rows],
    3,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), rows)
  assert_eq(
    local_managed_test_rows(second_ops),
    if singleton {
      ["{\"tag\":\"a\",\"id\":1}", "{\"tag\":\"a\",\"id\":2}"]
    } else {
      [
        "{\"tag\":\"a\",\"id\":1}", "{\"tag\":\"b\",\"id\":1}", "{\"tag\":\"a\",\"id\":2}",
        "{\"tag\":\"b\",\"id\":2}",
      ]
    },
  )
  first_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(producer))
  second_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  producer_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (producer_ops.close)()
  (producer_ops.cleanup_refresh)() |> ignore
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
test "Local managed cross join reaches two consumers in left-major order" {
  run_local_managed_cross_join(false)
}

///|
test "Local managed singleton cross join validates before two consumers" {
  run_local_managed_cross_join(true)
}

///|
test "standard Host selects bounded external cross join for two consumers" {
  let (run, issuer) = captured_graph_fixture(
    local_values_cross_external_chain=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 300000L,
      retained_bytes: 64000000L,
      execution_bytes: 268435456L,
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
      wire: {
        max_bytes: 200,
        max_nodes: 20,
        max_depth: 4,
        max_columns: 2,
        max_order_work: 100,
      },
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 256,
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
  let left_rows = local_managed_test_rows(left_ops)
  assert_eq(left_rows, ["{\"id\":1}", "{\"id\":2}"])
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
  let right_rows = local_managed_test_rows(right_ops)
  assert_eq(right_rows, [
    "{\"tag\":\"a\"}", "{\"tag\":\"b\"}", "{\"tag\":\"c\"}",
  ])
  let setup = @local_driver.prepare_local_managed_dispatch(
      installed,
      [left, right],
      @strategy.captured_next_managed_obligations(run, 10).unwrap(),
      0L,
    )
    .unwrap()
    .unwrap()
  assert_true(@local_driver.local_managed_dispatch_uses_provider(setup))
  let crossed_live = Ref(true)
  let advances = Ref(0)
  let (crossed_ops, crossed) = run_local_managed_test_task(
    installed,
    run,
    3,
    [left, right],
    [left_rows, right_rows],
    3,
    crossed_live,
    execution_quantum=1,
    execution_advances=Some(advances),
  )
  assert_true(advances.val > 10)
  let crossed_rows = local_managed_test_rows(crossed_ops)
  assert_eq(crossed_rows, [
    "{\"id\":1,\"tag\":\"a\"}", "{\"id\":1,\"tag\":\"b\"}", "{\"id\":1,\"tag\":\"c\"}",
    "{\"id\":2,\"tag\":\"a\"}", "{\"id\":2,\"tag\":\"b\"}", "{\"id\":2,\"tag\":\"c\"}",
  ])
  let first_live = Ref(true)
  let (first_ops, _) = run_local_managed_test_task(
    installed,
    run,
    4,
    [crossed],
    [crossed_rows],
    4,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [crossed],
    [crossed_rows],
    5,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), crossed_rows)
  assert_eq(local_managed_test_rows(second_ops), [
    "{\"tag\":\"a\",\"id\":1}", "{\"tag\":\"b\",\"id\":1}", "{\"tag\":\"c\",\"id\":1}",
    "{\"tag\":\"a\",\"id\":2}", "{\"tag\":\"b\",\"id\":2}", "{\"tag\":\"c\",\"id\":2}",
  ])
  first_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(crossed))
  second_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  crossed_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (crossed_ops.close)()
  (crossed_ops.cleanup_refresh)() |> ignore
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
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "standard Host splits cross join and filter before two consumers" {
  let (run, issuer) = captured_graph_fixture(
    local_values_cross_external_chain=true,
    local_values_cross_external_filter=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 12,
      holdings: 12,
      transfer_bytes: 300000L,
      retained_bytes: 64000000L,
      execution_bytes: 268435456L,
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
      wire: {
        max_bytes: 200,
        max_nodes: 20,
        max_depth: 4,
        max_columns: 2,
        max_order_work: 100,
      },
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 256,
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
  let crossed_setup = @local_driver.prepare_local_managed_dispatch(
      installed,
      [left, right],
      @strategy.captured_next_managed_obligations(run, 10).unwrap(),
      0L,
    )
    .unwrap()
    .unwrap()
  assert_true(@local_driver.local_managed_dispatch_uses_provider(crossed_setup))
  let crossed_live = Ref(true)
  let crossed_advances = Ref(0)
  let (crossed_ops, crossed) = run_local_managed_test_task(
    installed,
    run,
    3,
    [left, right],
    [local_managed_test_rows(left_ops), local_managed_test_rows(right_ops)],
    3,
    crossed_live,
    execution_quantum=1,
    execution_advances=Some(crossed_advances),
  )
  assert_true(crossed_advances.val > 1)
  let crossed_rows = local_managed_test_rows(crossed_ops)
  let filtered_live = Ref(true)
  let filtered_advances = Ref(0)
  let (filtered_ops, filtered) = run_local_managed_test_task(
    installed,
    run,
    4,
    [crossed],
    [crossed_rows],
    4,
    filtered_live,
    execution_quantum=1,
    execution_advances=Some(filtered_advances),
  )
  assert_true(filtered_advances.val > 1)
  let filtered_rows = local_managed_test_rows(filtered_ops)
  assert_eq(filtered_rows, crossed_rows)
  let first_live = Ref(true)
  let (first_ops, _) = run_local_managed_test_task(
    installed,
    run,
    5,
    [filtered],
    [filtered_rows],
    5,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    6,
    [filtered],
    [filtered_rows],
    6,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), filtered_rows)
  assert_eq(local_managed_test_rows(second_ops).length(), 6)
  first_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (first_ops.close)()
  ignore((first_ops.cleanup_refresh)())
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(filtered))
  second_live.val = false
  filtered_live.val = false
  crossed_live.val = false
  right_live.val = false
  left_live.val = false
  for
    (task, operations) in [
      (6, second_ops),
      (4, filtered_ops),
      (3, crossed_ops),
      (2, right_ops),
      (1, left_ops),
    ] {
    @strategy.close_captured_task_output(run, task)
    (operations.close)()
    ignore((operations.cleanup_refresh)())
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
fn run_standard_host_cross_join_cancel_after_pair_work(
  filtered : Bool,
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_cross_external_chain=true,
    local_values_cross_external_filter=filtered,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 300000L,
      retained_bytes: 64000000L,
      execution_bytes: 268435456L,
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
      wire: {
        max_bytes: 200,
        max_nodes: 20,
        max_depth: 4,
        max_columns: 2,
        max_order_work: 100,
      },
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 256,
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
  let mut pair_seen = false
  let mut polls = 0
  while !pair_seen && polls < 100 {
    polls += 1
    let observation = (operations.advance)(1).unwrap()
    assert_false(observation.complete)
    assert_true(observation.work <= 1L)
    pair_seen = observation.progress > 0L
  }
  assert_true(pair_seen)
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
test "standard Host cancels external cross join after pair work" {
  run_standard_host_cross_join_cancel_after_pair_work(false)
  run_standard_host_cross_join_cancel_after_pair_work(true)
}

///|
test "captured cross join retains the authored output restriction" {
  let (run, issuer) = captured_graph_fixture(
    local_values_cross_chain=true,
    local_values_cross_output_guard=Some(2),
  )
  assert_eq(@strategy.captured_task_join_output_limit(run, 1, 4), Some(2L))
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
}

///|
test "Local managed cross join cancellation publishes nothing and reclaims" {
  let (run, issuer) = captured_graph_fixture(local_values_cross_chain=true)
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
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap()
  let setup = @local_driver.prepare_local_managed_dispatch(
      installed,
      [],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  (operations.close)()
  assert_true((operations.execute)() is Err(_))
  assert_true(
    (operations.complete)(1, operations.storage_bytes, fn() { true }) is Err(_),
  )
  (operations.settle)().unwrap()
  (operations.cleanup_refresh)() |> ignore
  assert_false(@strategy.captured_task_completed(run, 1))
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "Local managed cross join copy stops after execution has started" {
  let (run, issuer) = captured_graph_fixture(local_values_cross_chain=true)
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
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap()
  let setup = @local_driver.prepare_local_managed_dispatch(
      installed,
      [],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  let first = (operations.advance)(1).unwrap()
  assert_false(first.complete)
  assert_eq(first.work, 1L)
  let second = (operations.advance)(1).unwrap()
  assert_false(second.complete)
  assert_eq(second.work, 1L)
  assert_true((operations.request_cancel)())
  assert_true((operations.advance)(1) is Err(_))
  assert_true((operations.execution_stopped)())
  assert_true((operations.output_row)(0) is Err(_))
  assert_true(
    (operations.complete)(1, operations.storage_bytes, fn() { true }) is Err(_),
  )
  (operations.settle)().unwrap()
  assert_true((operations.cleanup_refresh)())
  assert_false(@strategy.captured_task_completed(run, 1))
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
