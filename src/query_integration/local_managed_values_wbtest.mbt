///|
test "Local managed execution admits checked zero-input values without a dummy producer" {
  let (run, issuer) = captured_graph_fixture(values=true)
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

  // The control predecessor is independent of the zero-input data shape.
  captured_graph_local(run, 1).unwrap()
  assert_eq(@strategy.next_captured_task(run), Some(2))
  let graph = @strategy.captured_dag_graph(run)
  let owner = @strategy.graph_task_owner(graph, 2).unwrap()
  let prepared = @local_driver.prepare_local_managed_dispatch(
      installed,
      [],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(prepared).unwrap()
  assert_eq(operations.inputs.length(), 0)
  (operations.execute)().unwrap()
  assert_eq((operations.output_rows)(), 1)
  assert_eq((operations.output_row)(0).unwrap(), "{\"id\":7}")
  let available = Ref(true)
  (operations.prepare_finalization)(7, operations.storage_bytes, fn() {
    available.val
  }).unwrap()
  let mut last_progress = -1L
  while true {
    let observation = (operations.advance_finalization)(1).unwrap()
    assert_true(observation.progress >= last_progress)
    assert_true(observation.work >= 0L)
    assert_true(observation.work <= 1L)
    if !observation.complete {
      assert_true(observation.work > 0L)
    }
    last_progress = observation.progress
    if observation.complete {
      break
    }
  }
  (operations.settle)().unwrap()
  let completed = (operations.complete)(7, operations.storage_bytes, fn() {
    available.val
  }).unwrap()
  assert_true(
    @strategy.captured_managed_task_output_matches(
      run,
      2,
      @pipeline.Step(0),
      completed,
    ),
  )
  assert_eq(@execution.managed_completed_output_row_count(completed), 1)
  assert_true(@execution.managed_completed_output_available(completed))

  @strategy.close_captured_task_output(run, 2)
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
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
test "Local managed zero-input values feed two downstream Computes" {
  let (run, issuer) = captured_graph_fixture(
    local_values_two_consumer_chain=true,
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

  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
  )
  let rows = local_managed_test_rows(values_ops)
  assert_eq(rows, [
    "{\"id\":null,\"label\":\"none\"}", "{\"id\":1,\"label\":\"one\"}",
  ])

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [rows],
    2,
    first_live,
    finalization_quantum=33,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    3,
    [values],
    [rows],
    3,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), rows)
  assert_eq(local_managed_test_rows(second_ops), [
    "{\"label\":\"none\",\"id\":null}", "{\"label\":\"one\",\"id\":1}",
  ])

  first_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(values))

  second_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
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
test "checked VecA expressions reach two standard Host consumers" {
  let (run, issuer) = captured_graph_fixture(
    local_vector_expression_chain=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 128000000L,
      execution_bytes: 134217728L,
    }),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let provider = @local_veca_provider.provider(
    carrier_vectors_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      sequences[1],
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 500,
        max_nodes: 100,
        max_depth: 10,
        max_columns: 5,
      },
      row: {
        max_bytes: 500,
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 500,
      },
      max_batch_bytes: 1000,
    },
    None,
  ).unwrap()

  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
    finalization_quantum=1,
  )
  let value_rows = local_managed_test_rows(values_ops)
  assert_eq(value_rows, [
    "{\"id\":1,\"left\":[1,2],\"right\":[3,4]}", "{\"id\":2,\"left\":[2,1],\"right\":[4,3]}",
  ])

  let score_live = Ref(true)
  let (score_ops, scored) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [value_rows],
    2,
    score_live,
    finalization_quantum=1,
  )
  let score_rows = local_managed_test_rows(score_ops)
  assert_eq(score_rows, [
    "{\"id\":1,\"left\":[1,2],\"right\":[3,4],\"score\":11}", "{\"id\":2,\"left\":[2,1],\"right\":[4,3],\"score\":11}",
  ])

  let producer_live = Ref(true)
  let (producer_ops, producer) = run_local_managed_test_task(
    installed,
    run,
    3,
    [scored],
    [score_rows],
    3,
    producer_live,
    finalization_quantum=1,
  )
  let rows = local_managed_test_rows(producer_ops)
  assert_eq(rows, [
    "{\"id\":1,\"joined\":[3,4,1,2],\"left\":[1,2]," +
    "\"right\":[3,4],\"score\":11}",
    "{\"id\":2,\"joined\":[4,3,2,1],\"left\":[2,1]," +
    "\"right\":[4,3],\"score\":11}",
  ])

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [producer],
    [rows],
    4,
    first_live,
    finalization_quantum=2,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [producer],
    [rows],
    5,
    second_live,
    finalization_quantum=31,
  )
  assert_eq(local_managed_test_rows(first_ops), [
    "{\"id\":1,\"score\":11,\"joined\":[3,4,1,2]}", "{\"id\":2,\"score\":11,\"joined\":[4,3,2,1]}",
  ])
  assert_eq(local_managed_test_rows(second_ops), [
    "{\"joined\":[3,4,1,2],\"score\":11,\"id\":1}", "{\"joined\":[4,3,2,1],\"score\":11,\"id\":2}",
  ])

  first_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(producer))

  second_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  producer_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (producer_ops.close)()
  (producer_ops.cleanup_refresh)() |> ignore
  score_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (score_ops.close)()
  (score_ops.cleanup_refresh)() |> ignore
  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
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
test "Local managed empty values retain schema for two consumers" {
  let (run, issuer) = captured_graph_fixture(
    local_values_managed_variant="empty",
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
    finalization_quantum=1,
  )
  assert_eq(local_managed_test_rows(producer_ops), [])
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    2,
    [producer],
    [[]],
    2,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    3,
    [producer],
    [[]],
    3,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), [])
  assert_eq(local_managed_test_rows(second_ops), [])

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
test "Local finalization preserves 31 rows across adjacent quanta" {
  let (run, issuer) = captured_graph_fixture(
    local_values_managed_variant="thirty_one",
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
    finalization_quantum=32,
  )
  let rows = local_managed_test_rows(producer_ops)
  assert_eq(rows.length(), 31)
  assert_true(@execution.managed_completed_output_available(producer))

  producer_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (producer_ops.close)()
  (producer_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  for task in [0, 2, 3] {
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
test "Local managed nested values preserve typed rows for two consumers" {
  let (run, issuer) = captured_graph_fixture(
    local_values_managed_variant="nested",
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
      row: {
        max_bytes: 1000,
        max_nodes: 100,
        max_depth: 8,
        max_text_bytes: 1000,
      },
      max_batch_bytes: 1000,
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
  assert_eq(rows, [
    "{\"items\":[{\"name\":\"a\",\"score\":1},{\"name\":\"b\",\"score\":2}],\"meta\":{\"active\":true}}",
  ])
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
  assert_eq(local_managed_test_rows(second_ops), [
    "{\"meta\":{\"active\":true},\"items\":[{\"name\":\"a\",\"score\":1},{\"name\":\"b\",\"score\":2}]}",
  ])

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
