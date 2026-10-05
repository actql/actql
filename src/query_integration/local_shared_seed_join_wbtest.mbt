///|
test "product retained shared seed JOIN executes once per task and releases custody" {
  // The same independently authored ten-step shape as the graph regression;
  // its expected row is fixed here without reading compiler output.
  let document =
    #|{"version":"actql/0.1","id":"shared-seed-join","stages":[{"id":"main","inputs":{},"steps":[{"as":"unit","values":{"schema":{"unit":{"type":"boolean","nullable":false}},"rows":[{"unit":true}]}},{"from":"unit","derive":{"key":{"literal":1}},"as":"keyed"},{"from":"keyed","select":[{"id":"key"}],"as":"seed"},{"from":"seed","derive":{"left_score":{"literal":10}},"as":"left_derived"},{"from":"left_derived","select":["id","left_score"],"as":"left"},{"from":"seed","derive":{"right_score":{"literal":20}},"as":"right_derived"},{"from":"right_derived","select":["id","right_score"],"as":"right"},{"from":"left","join":{"kind":"inner","with":"right","on":[{"left":"id","right":"id"}],"select":{"joined_score":"left.left_score"},"max_output_rows":1},"as":"joined"},{"from":"joined","derive":{"score":{"field":"joined_score"}},"as":"derived"},{"from":"derived","select":["score"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let (_, environment, limits) = local_effect_export_fixture()
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    { ..limits.program, max_tasks: 10, },
  ).unwrap()
  let setup = @client_local_host.open_source_free_local_retained_host(
    prepared,
    @identity.stringify_value(registered_body(), 100000, 10000, 100),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    1L,
    0L,
    0L,
    0L,
    fragment_body=Some(
      @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
    ),
  ).unwrap()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(setup),
  ).unwrap()
  let graph = @strategy.captured_dag_graph(run)
  let ledger = @strategy.captured_dag_ledger(run)
  assert_eq(@strategy.graph_task_count(graph), 10)
  assert_eq(@strategy.captured_compute_first_task(run), 0)
  assert_true(@strategy.captured_dag_strategy(run) is Some(_))
  assert_eq(@resources.ledger_limits(ledger).execution_bytes, 536870912L)
  let sources = [[], [0], [1], [2], [3], [2], [5], [4, 6], [7], [8]]
  let operations : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
  let outputs : Array[@execution.ManagedCompletedOutput[Int]] = []
  let rows : Array[Array[String]] = []
  let lives : Array[Ref[Bool]] = []
  for task, inputs in sources {
    assert_false(@strategy.captured_task_completed(run, task))
    assert_eq(@local_driver.local_dispatch_rejection(installed, task), None)
    let live = Ref(true)
    let (operation, output) = run_local_managed_test_task(
      installed,
      run,
      task,
      inputs.map(index => outputs[index]),
      inputs.map(index => rows[index]),
      task,
      live,
      execution_quantum=1,
      require_provider=true,
    )
    assert_true(@strategy.captured_task_completed(run, task))
    operations.push(operation)
    outputs.push(output)
    rows.push(local_managed_test_rows(operation))
    lives.push(live)
    if task == 5 {
      // Both branches consume this exact retained seed generation.
      assert_true(@execution.managed_completed_output_available(outputs[2]))
      assert_eq(rows[2], ["{\"id\":1}"])
    }
  }
  assert_eq(rows[9], ["{\"score\":10}"])
  assert_eq(@strategy.next_captured_task(run), None)
  assert_eq(@resources.ledger_usage(ledger).attempts, 10)
  for offset in 0..<10 {
    let task = 9 - offset
    lives[task].val = false
    @strategy.close_captured_task_output(run, task)
    (operations[task].close)()
    assert_true((operations[task].cleanup_refresh)())
    assert_false(@execution.managed_completed_output_available(outputs[task]))
    if task > 0 {
      assert_true(
        @execution.managed_completed_output_available(outputs[task - 1]),
      )
    }
  }
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}
