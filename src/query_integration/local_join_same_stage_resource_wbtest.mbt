///|
/// Run the same-stage full join fixture with the given execution work and
/// operation-entry limits; branches complete, then the join task (5) runs at
/// quantum one. Returns "complete", or the limit issue ("input_limit" or
/// "row_limit") that stopped the join, with the work the join charged.
fn run_same_stage_join_budget(
  max_work : Int,
  max_entries : Int,
) -> (String, Int64) raise {
  let ledger_limits : @resources.LedgerLimits = {
    planning_work: 10000,
    attempts: 20,
    holdings: 20,
    transfer_bytes: 300000L,
    retained_bytes: 134217728L,
    execution_bytes: 536870912L,
  }
  let (run, issuer) = captured_graph_fixture(
    local_values_join_chain=true,
    local_values_join_kind="full",
    ledger_limits=Some(ledger_limits),
  )
  let registry = search_registry()
  let defaults = dispatch_test_limits()
  let execution : @execution.SequenceExecutionLimits = {
    rows: { ..defaults.local_execution.rows, operation_entries: max_entries, },
    max_work,
    max_frames: defaults.local_execution.max_frames,
  }
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    execution,
    defaults.guards,
    defaults.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 1000,
        max_nodes: 200,
        max_columns: 4,
      },
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 256,
    },
    None,
  ).unwrap()
  let ops : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
  let outputs : Array[@execution.ManagedCompletedOutput[Int]] = []
  let rows : Array[Array[String]] = []
  let lives : Array[Ref[Bool]] = []
  for task in 1..<5 {
    let sources = match task {
      1 | 3 => []
      2 => [0]
      _ => [2]
    }
    let live = Ref(true)
    let (operations, output) = run_local_managed_test_task(
      installed,
      run,
      task,
      sources.map(index => outputs[index]),
      sources.map(index => rows[index]),
      task,
      live,
      execution_quantum=1,
      require_provider=true,
    )
    ops.push(operations)
    outputs.push(output)
    rows.push(local_managed_test_rows(operations))
    lives.push(live)
  }
  let join = start_local_managed_test_task_operations(
    installed,
    run,
    5,
    [outputs[1], outputs[3]],
    [rows[1], rows[3]],
    require_provider=true,
  )
  let mut outcome = ""
  let mut charged = 0L
  while outcome == "" {
    match (join.advance)(1) {
      Ok(observation) => {
        assert_true(observation.work <= 1L)
        charged += observation.work
        if observation.complete {
          outcome = "complete"
        }
      }
      Err(
        @local_driver.Configuration(@connector.Execution(@execution.InputLimit))
      ) => outcome = "input_limit"
      Err(
        @local_driver.Configuration(
          @connector.Execution(@execution.Rows(_, @execution.RowLimit))
        )
      ) => outcome = "row_limit"
      Err(_) => outcome = "other"
    }
  }
  if outcome == "complete" {
    assert_eq(local_managed_test_rows(join), [
      "{\"id\":1,\"l\":\"l1\",\"r\":\"r1\"}", "{\"id\":1,\"l\":\"l1\",\"r\":\"r2\"}",
      "{\"id\":1,\"l\":\"l2\",\"r\":\"r1\"}", "{\"id\":1,\"l\":\"l2\",\"r\":\"r2\"}",
      "{\"id\":2,\"l\":\"l3\",\"r\":null}", "{\"id\":null,\"l\":null,\"r\":\"r3\"}",
      "{\"id\":null,\"l\":null,\"r\":\"r4\"}",
    ])
    let live = Ref(true)
    (join.prepare_finalization)(5, join.storage_bytes, fn() { live.val }).unwrap()
    while !(join.advance_finalization)(1).unwrap().complete {

    }
    (join.settle)().unwrap()
    let output = (join.complete)(5, join.storage_bytes, fn() { live.val }).unwrap()
    assert_true(@execution.managed_completed_output_available(output))
    live.val = false
    @strategy.close_captured_task_output(run, 5)
    (join.close)()
    (join.cleanup_refresh)() |> ignore
  } else {
    assert_true((join.output_row)(0) is Err(_))
    assert_false(@strategy.captured_task_completed(run, 5))
    (join.settle)().unwrap()
    (join.close)()
    assert_true((join.cleanup_refresh)())
  }
  for output in outputs {
    assert_true(@execution.managed_completed_output_available(output))
  }
  for offset in 0..<4 {
    let index = 3 - offset
    lives[index].val = false
    @strategy.close_captured_task_output(run, index + 1)
    (ops[index].close)()
    assert_true((ops[index].cleanup_refresh)())
  }
  @strategy.stop_captured_dag(run)
  for task in 0..<10 {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
  (outcome, charged)
}

///|
test "same-stage full join admits exact work and one-short limits" {
  // The task-wide ceiling covers preparation and the join's observed advances
  // (278); the join reports an exhausted control ceiling as its row limit.
  assert_eq(run_same_stage_join_budget(302, 10000), ("complete", 278L))
  assert_eq(run_same_stage_join_budget(301, 10000).0, "row_limit")
}

///|
test "same-stage full join admits exact workspace and one-short limit" {
  // The branches complete under both limits; only the join exceeds 35.
  assert_eq(run_same_stage_join_budget(100000, 36).0, "complete")
  assert_eq(run_same_stage_join_budget(100000, 35).0, "row_limit")
}
