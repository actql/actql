///|
fn run_local_managed_join_case(
  kind : String,
  expected_joined : Array[String],
  expected_second : Array[String],
  imported_full? : Bool = false,
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
    local_values_join_chain=true,
    local_values_join_kind=kind,
    local_values_join_imported_full=imported_full,
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

  let left_source_live = Ref(true)
  let (left_source_ops, left_source) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    left_source_live,
    require_provider=imported_full,
    execution_quantum=if imported_full { 1 } else { 0 },
  )
  let left_source_rows = local_managed_test_rows(left_source_ops)
  let left_live = if imported_full { Ref(true) } else { left_source_live }
  let (left_ops, left) = if imported_full {
    run_local_managed_test_task(
      installed,
      run,
      2,
      [left_source],
      [left_source_rows],
      2,
      left_live,
      require_provider=true,
      execution_quantum=1,
    )
  } else {
    (left_source_ops, left_source)
  }
  let left_rows = local_managed_test_rows(left_ops)
  assert_eq(
    left_rows,
    if imported_full {
      [
        "{\"id\":1,\"l\":\"l1\"}", "{\"id\":1,\"l\":\"l2\"}", "{\"id\":2,\"l\":\"l3\"}",
      ]
    } else {
      [
        "{\"id\":1,\"l\":\"l1\"}", "{\"id\":1,\"l\":\"l2\"}", "{\"id\":null,\"l\":\"ln\"}",
        "{\"id\":2,\"l\":\"l3\"}",
      ]
    },
  )

  let right_source_live = Ref(true)
  let right_source_task = if imported_full { 3 } else { 2 }
  let (right_source_ops, right_source) = run_local_managed_test_task(
    installed,
    run,
    right_source_task,
    [],
    [],
    right_source_task,
    right_source_live,
    require_provider=imported_full,
    execution_quantum=if imported_full { 1 } else { 0 },
  )
  let right_source_rows = local_managed_test_rows(right_source_ops)
  let right_live = if imported_full { Ref(true) } else { right_source_live }
  let (right_ops, right) = if imported_full {
    run_local_managed_test_task(
      installed,
      run,
      4,
      [right_source],
      [right_source_rows],
      4,
      right_live,
      require_provider=true,
      execution_quantum=1,
    )
  } else {
    (right_source_ops, right_source)
  }
  let right_rows = local_managed_test_rows(right_ops)
  assert_eq(
    right_rows,
    if imported_full {
      [
        "{\"id\":1,\"r\":\"r1\"}", "{\"id\":1,\"r\":\"r2\"}", "{\"id\":3,\"r\":\"r3\"}",
        "{\"id\":4,\"r\":\"r4\"}",
      ]
    } else {
      [
        "{\"id\":1,\"r\":\"r1\"}", "{\"id\":1,\"r\":\"r2\"}", "{\"id\":null,\"r\":\"rn\"}",
        "{\"id\":3,\"r\":\"r3\"}", "{\"id\":4,\"r\":\"r4\"}",
      ]
    },
  )

  let join_live = Ref(true)
  let join_task = if imported_full { 5 } else { 3 }
  let (join_ops, joined) = run_local_managed_test_task(
    installed,
    run,
    join_task,
    [left, right],
    [left_rows, right_rows],
    join_task,
    join_live,
    require_provider=true,
    execution_quantum=1,
  )
  let joined_rows = local_managed_test_rows(join_ops)
  assert_eq(joined_rows, expected_joined)

  let first_live = Ref(true)
  let first_task = if imported_full { 6 } else { 4 }
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    first_task,
    [joined],
    [joined_rows],
    first_task,
    first_live,
  )
  let second_live = Ref(true)
  let second_task = if imported_full { 7 } else { 5 }
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    second_task,
    [joined],
    [joined_rows],
    second_task,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), joined_rows)
  assert_eq(local_managed_test_rows(second_ops), expected_second)

  first_live.val = false
  @strategy.close_captured_task_output(run, first_task)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(joined))

  second_live.val = false
  @strategy.close_captured_task_output(run, second_task)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  join_live.val = false
  @strategy.close_captured_task_output(run, join_task)
  (join_ops.close)()
  (join_ops.cleanup_refresh)() |> ignore
  left_live.val = false
  @strategy.close_captured_task_output(run, if imported_full { 2 } else { 1 })
  (left_ops.close)()
  (left_ops.cleanup_refresh)() |> ignore
  right_live.val = false
  @strategy.close_captured_task_output(run, if imported_full { 4 } else { 2 })
  (right_ops.close)()
  (right_ops.cleanup_refresh)() |> ignore
  if imported_full {
    left_source_live.val = false
    @strategy.close_captured_task_output(run, 1)
    (left_source_ops.close)()
    (left_source_ops.cleanup_refresh)() |> ignore
    right_source_live.val = false
    @strategy.close_captured_task_output(run, 3)
    (right_source_ops.close)()
    (right_source_ops.cleanup_refresh)() |> ignore
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
fn run_local_full_join_branches(cancel : Bool) -> Unit raise {
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

  // Both authored branches are executed through the ordinary typed DAG.
  // No test-only provider or independent re-created join inputs are used.
  let upstream_ops : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
  let upstream_outputs : Array[@execution.ManagedCompletedOutput[Int]] = []
  let upstream_rows : Array[Array[String]] = []
  let upstream_lives : Array[Ref[Bool]] = []
  for task in 1..<8 {
    let sources = match task {
      1 | 3 => []
      2 => [0]
      4 => [2]
      5 => [1, 3]
      _ => [task - 2]
    }
    let live = Ref(true)
    if cancel && task == 5 {
      let operations = start_local_managed_test_task_operations(
        installed,
        run,
        task,
        sources.map(index => upstream_outputs[index]),
        sources.map(index => upstream_rows[index]),
        require_provider=true,
      )
      for _ in 0..<8 {
        let observation = (operations.advance)(1).unwrap()
        assert_false(observation.complete)
        assert_eq(observation.work, 1L)
      }
      assert_true((operations.request_cancel)())
      assert_true((operations.advance)(1) is Err(_))
      assert_true((operations.execution_stopped)())
      assert_true((operations.output_row)(0) is Err(_))
      assert_true(
        (operations.complete)(5, operations.storage_bytes, fn() { true })
        is Err(_),
      )
      (operations.settle)().unwrap()
      assert_true((operations.cleanup_refresh)())
      assert_false(@strategy.captured_task_completed(run, 5))
      for output in upstream_outputs {
        assert_true(@execution.managed_completed_output_available(output))
      }
      for offset in 0..<4 {
        let index = 3 - offset
        upstream_lives[index].val = false
        @strategy.close_captured_task_output(run, index + 1)
        (upstream_ops[index].close)()
        assert_true((upstream_ops[index].cleanup_refresh)())
      }
      @strategy.stop_captured_dag(run)
      @strategy.close_captured_task_output(run, 0)
      @strategy.refresh_captured_retention(run)
      let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
      assert_eq(usage.reserved_execution_bytes, 0L)
      assert_eq(usage.reserved_retention_bytes, 0L)
      assert_eq(usage.held_bytes, 0L)
      @mock.close_mock_query_issuer(issuer)
      return
    }
    let (ops, output) = run_local_managed_test_task(
      installed,
      run,
      task,
      sources.map(index => upstream_outputs[index]),
      sources.map(index => upstream_rows[index]),
      task,
      live,
      execution_quantum=1,
      require_provider=true,
    )
    upstream_ops.push(ops)
    upstream_outputs.push(output)
    upstream_rows.push(local_managed_test_rows(ops))
    upstream_lives.push(live)
  }
  let producer_ops = upstream_ops[6]
  let producer = upstream_outputs[6]
  let rows = local_managed_test_rows(producer_ops)
  assert_eq(rows, [
    "{\"id\":1,\"l\":\"l1\",\"r\":\"r1\"}", "{\"id\":1,\"l\":\"l1\",\"r\":\"r2\"}",
    "{\"id\":1,\"l\":\"l2\",\"r\":\"r1\"}", "{\"id\":1,\"l\":\"l2\",\"r\":\"r2\"}",
    "{\"id\":2,\"l\":\"l3\",\"r\":null}", "{\"id\":null,\"l\":null,\"r\":\"r3\"}",
    "{\"id\":null,\"l\":null,\"r\":\"r4\"}",
  ])

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    8,
    [producer],
    [rows],
    8,
    first_live,
    execution_quantum=1,
    require_provider=true,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    9,
    [producer],
    [rows],
    9,
    second_live,
    execution_quantum=1,
    require_provider=true,
  )
  assert_eq(local_managed_test_rows(first_ops), rows)
  assert_eq(local_managed_test_rows(second_ops), [
    "{\"r\":\"r1\",\"l\":\"l1\",\"id\":1}", "{\"r\":\"r2\",\"l\":\"l1\",\"id\":1}",
    "{\"r\":\"r1\",\"l\":\"l2\",\"id\":1}", "{\"r\":\"r2\",\"l\":\"l2\",\"id\":1}",
    "{\"r\":null,\"l\":\"l3\",\"id\":2}", "{\"r\":\"r3\",\"l\":null,\"id\":null}",
    "{\"r\":\"r4\",\"l\":null,\"id\":null}",
  ])

  first_live.val = false
  @strategy.close_captured_task_output(run, 8)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(producer))

  second_live.val = false
  @strategy.close_captured_task_output(run, 9)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  for offset in 0..<7 {
    let index = 6 - offset
    upstream_lives[index].val = false
    @strategy.close_captured_task_output(run, index + 1)
    (upstream_ops[index].close)()
    (upstream_ops[index].cleanup_refresh)() |> ignore
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
test "Local managed full join retains stable identities for two consumers" {
  run_local_full_join_branches(false)
}

///|
test "Local same-stage full join cancels without reclaiming its branches" {
  run_local_full_join_branches(true)
}

///|
test "Local managed full join imports both producer identities" {
  run_local_managed_join_case(
    "full",
    [
      "{\"id\":1,\"l\":\"l1\",\"r\":\"r1\"}", "{\"id\":1,\"l\":\"l1\",\"r\":\"r2\"}",
      "{\"id\":1,\"l\":\"l2\",\"r\":\"r1\"}", "{\"id\":1,\"l\":\"l2\",\"r\":\"r2\"}",
      "{\"id\":2,\"l\":\"l3\",\"r\":null}", "{\"id\":null,\"l\":null,\"r\":\"r3\"}",
      "{\"id\":null,\"l\":null,\"r\":\"r4\"}",
    ],
    [
      "{\"r\":\"r1\",\"l\":\"l1\",\"id\":1}", "{\"r\":\"r2\",\"l\":\"l1\",\"id\":1}",
      "{\"r\":\"r1\",\"l\":\"l2\",\"id\":1}", "{\"r\":\"r2\",\"l\":\"l2\",\"id\":1}",
      "{\"r\":null,\"l\":\"l3\",\"id\":2}", "{\"r\":\"r3\",\"l\":null,\"id\":null}",
      "{\"r\":\"r4\",\"l\":null,\"id\":null}",
    ],
    imported_full=true,
  )
}

///|
test "Local managed equality joins bind both ports and feed two Computes" {
  run_local_managed_join_case(
    "inner",
    [
      "{\"id\":1,\"l\":\"l1\",\"r\":\"r1\"}", "{\"id\":1,\"l\":\"l1\",\"r\":\"r2\"}",
      "{\"id\":1,\"l\":\"l2\",\"r\":\"r1\"}", "{\"id\":1,\"l\":\"l2\",\"r\":\"r2\"}",
    ],
    [
      "{\"r\":\"r1\",\"l\":\"l1\",\"id\":1}", "{\"r\":\"r2\",\"l\":\"l1\",\"id\":1}",
      "{\"r\":\"r1\",\"l\":\"l2\",\"id\":1}", "{\"r\":\"r2\",\"l\":\"l2\",\"id\":1}",
    ],
  )
  run_local_managed_join_case(
    "left",
    [
      "{\"id\":1,\"l\":\"l1\",\"r\":\"r1\"}", "{\"id\":1,\"l\":\"l1\",\"r\":\"r2\"}",
      "{\"id\":1,\"l\":\"l2\",\"r\":\"r1\"}", "{\"id\":1,\"l\":\"l2\",\"r\":\"r2\"}",
      "{\"id\":null,\"l\":\"ln\",\"r\":null}", "{\"id\":2,\"l\":\"l3\",\"r\":null}",
    ],
    [
      "{\"r\":\"r1\",\"l\":\"l1\",\"id\":1}", "{\"r\":\"r2\",\"l\":\"l1\",\"id\":1}",
      "{\"r\":\"r1\",\"l\":\"l2\",\"id\":1}", "{\"r\":\"r2\",\"l\":\"l2\",\"id\":1}",
      "{\"r\":null,\"l\":\"ln\",\"id\":null}", "{\"r\":null,\"l\":\"l3\",\"id\":2}",
    ],
  )
  run_local_managed_join_case(
    "semi",
    ["{\"id\":1,\"l\":\"l1\"}", "{\"id\":1,\"l\":\"l2\"}"],
    ["{\"l\":\"l1\",\"id\":1}", "{\"l\":\"l2\",\"id\":1}"],
  )
  run_local_managed_join_case(
    "anti",
    ["{\"id\":null,\"l\":\"ln\"}", "{\"id\":2,\"l\":\"l3\"}"],
    ["{\"l\":\"ln\",\"id\":null}", "{\"l\":\"l3\",\"id\":2}"],
  )
}
