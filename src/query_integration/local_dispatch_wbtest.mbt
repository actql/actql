///|
test "Local retained input policy validates before mutation and seals before offers escape" {
  for install_policy in [false, true] {
    let (run, _) = captured_graph_fixture()
    let registry = search_registry()
    let driver = @host_driver.open_dispatch_driver(run)
    let limits = dispatch_test_limits()
    let registration = @connector.capability_registration_at(registry, 0).unwrap()
    let installed = @local_driver.prepare_local_dispatch_module(
      driver,
      registry,
      registration,
      dispatch_test_generated(run),
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
    ).unwrap()
    let imports : @local_connector.LocalImportLimits = {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    }
    let ledger = @strategy.captured_dag_ledger(run)
    let before = @resources.ledger_usage(ledger)
    assert_true(
      @local_driver.configure_local_retained_inputs(
        installed,
        { ..imports, max_batch_bytes: 0, },
        Some(0L),
      )
      is Err(Configuration(InvalidLimits)),
    )
    if install_policy {
      @local_driver.configure_local_retained_inputs(installed, imports, None).unwrap()
    }
    @local_driver.estimate_local_dispatch_offer(
      installed,
      1,
      [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(1L), }],
      100,
    ).unwrap()
    |> ignore
    assert_true(
      @local_driver.configure_local_retained_inputs(
        installed,
        imports,
        Some(0L),
      )
      is Err(Configuration(InvalidLimits)),
    )
    let after = @resources.ledger_usage(ledger)
    assert_true(after.planning_work > before.planning_work)
    assert_eq(after, { ..before, planning_work: after.planning_work, })
  }
}

///|
test "Local connector installation validates task owners and cannot exchange prepared channels" {
  let (run, _) = captured_graph_fixture()
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let generated = dispatch_test_generated(run)
  let limits = dispatch_test_limits()
  let install = fn(sequences) {
    @local_driver.prepare_local_dispatch_module(
      driver,
      registry,
      registration,
      sequences,
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
    )
  }
  assert_true(install([]) is Err(Configuration(ForeignPreparation)))
  let swapped = generated.copy()
  swapped[0] = generated[1]
  assert_true(install(swapped) is Err(Configuration(ForeignPreparation)))
  let implementation = install(generated).unwrap()
  let other = install(generated).unwrap()
  generated.clear()
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(_context : Unit, task, revision, request) {
          @local_driver.prepare_local_dispatch(
            implementation, task, revision, request,
          )
        },
      ),
    ],
    1,
  ).unwrap()
  let host = @host_driver.open_dispatch_host(
    driver,
    entries,
    limits.capacity,
    100,
    10000,
  ).unwrap()
  let task = @host_driver.prepare_next_installed_task(host, ())
    .unwrap()
    .unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(
    @local_driver.execute_local_dispatch(other, host, task)
    is Err(Dispatch(StaleTask)),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  @local_driver.execute_local_dispatch(implementation, host, task).unwrap()
  assert_true(@strategy.captured_task_completed(run, 1))
  assert_true(
    @local_driver.execute_local_dispatch(implementation, host, task)
    is Err(Dispatch(StaleTask)),
  )
  let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  // The source fixture is [3, 1, 2]; A's id > 2 keeps exactly [3].
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3.0)))
  @strategy.close_captured_task_output(run, 1)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}

///|
test "standard Local Host exports the exact checked Named Result through the portable publication owner" {
  let (run, _) = captured_graph_fixture()
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_result_count(graph), 2)
  assert_eq(@strategy.graph_result_name(graph, 0), Some("b"))
  assert_eq(@strategy.graph_result_name(graph, 1), Some("c"))
  let registry = search_registry()
  let revision = channel_test_selection(run, registry)
  let registration = @strategy.strategy_registration(revision, 1).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let limits = dispatch_test_limits()
  let implementation = @local_driver.prepare_local_dispatch_module(
    driver,
    registry,
    registration,
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(_context : Unit, task, revision, request) {
          @local_driver.prepare_local_dispatch(
            implementation, task, revision, request,
          )
        },
      ),
    ],
    1,
  ).unwrap()
  let host = @host_driver.open_dispatch_host(
    driver,
    entries,
    limits.capacity,
    100,
    10000,
  ).unwrap()
  while @host_driver.prepare_next_installed_task(host, ()).unwrap()
        is Some(task) {
    @local_driver.execute_local_dispatch(implementation, host, task).unwrap()
  }
  let result_stream = @publication_host.prepare_captured_result_publication_export(
    run,
    1,
    {
      max_result_fields: 10,
      max_result_mapping_work: 100,
      max_result_order_work: 100,
      max_result_workspace_entries: 100,
      max_rows: 100,
      values: {
        max_nodes: 1000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: 10000,
      },
      payload_wire: {
        max_columns: 10,
        max_order_work: 100,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      logical_wire: {
        max_columns: 10,
        max_order_work: 100,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      schema: {
        max_fields: 10,
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
      },
      max_batch_bytes: 64,
    },
  ).unwrap()
  let text = StringBuilder()
  while result_stream.next().unwrap() is Some(chunk) {
    text.write_string(chunk)
  }
  text.write_string(result_stream.finish().unwrap())
  assert_eq(text.to_string(), "[{\"id\":3}]")
  assert_eq(result_stream.row_count().unwrap(), 1)
  assert_eq(result_stream.result_fields().unwrap(), ["id"])
  assert_true(
    result_stream.logical_relation_cid().unwrap().has_prefix("sha256:"),
  )
  assert_true(result_stream.result_schema_cid().unwrap().has_prefix("sha256:"))
  result_stream.cancel()
  for task = @strategy.graph_task_count(graph) - 1; task > 0; task = task - 1 {
    @strategy.close_captured_task_output(run, task)
  }
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}
