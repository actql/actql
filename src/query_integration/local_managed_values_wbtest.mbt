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
test "Local managed zero-input values stop after bounded cell work" {
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
  captured_graph_local(run, 1).unwrap()
  let operations = start_local_managed_test_task_operations(
    installed,
    run,
    2,
    [],
    [],
  )
  let first = (operations.advance)(1).unwrap()
  assert_false(first.complete)
  assert_eq(first.work, 1L)
  assert_true((operations.request_cancel)())
  assert_true((operations.advance)(1) is Err(_))
  assert_true((operations.execution_stopped)())
  assert_true((operations.output_row)(0) is Err(_))
  assert_true(
    (operations.complete)(7, operations.storage_bytes, fn() { true }) is Err(_),
  )
  (operations.settle)().unwrap()
  assert_true((operations.cleanup_refresh)())
  assert_false(@strategy.captured_task_completed(run, 2))
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
  let values_advances = Ref(0)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
    execution_quantum=1,
    execution_advances=Some(values_advances),
  )
  assert_eq(values_advances.val, 11)
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
fn run_standard_host_values_relation_step(
  assertion : Bool,
  unique? : Bool = false,
  relation_variant? : String = "",
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_two_consumer_chain=true,
    local_values_two_consumer_filter=!assertion &&
      !unique &&
      relation_variant == "",
    local_values_two_consumer_assert=assertion && !unique,
    local_values_two_consumer_assert_unique=unique,
    local_values_two_consumer_relation_variant=relation_variant,
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
  let values_advances = Ref(0)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
    execution_quantum=1,
    execution_advances=Some(values_advances),
  )
  assert_true(values_advances.val > 1)
  let values_rows = local_managed_test_rows(values_ops)
  assert_eq(values_rows, [
    "{\"id\":null,\"label\":\"none\"}", "{\"id\":1,\"label\":\"one\"}",
  ])
  let relation_live = Ref(true)
  let relation_advances = Ref(0)
  let (relation_ops, relation_output) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [values_rows],
    2,
    relation_live,
    execution_quantum=1,
    execution_advances=Some(relation_advances),
    require_provider=true,
  )
  assert_true(relation_advances.val > 1)
  let relation_rows = local_managed_test_rows(relation_ops)
  let expected = if relation_variant == "take" {
    ["{\"id\":null,\"label\":\"none\"}"]
  } else if relation_variant == "derive" {
    [
      "{\"copy\":\"none\",\"id\":null,\"label\":\"none\"}", "{\"copy\":\"one\",\"id\":1,\"label\":\"one\"}",
    ]
  } else if assertion ||
    unique ||
    relation_variant == "select" ||
    relation_variant == "distinct" {
    values_rows
  } else {
    ["{\"id\":1,\"label\":\"one\"}"]
  }
  assert_eq(relation_rows, expected)
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    3,
    [relation_output],
    [relation_rows],
    3,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    4,
    [relation_output],
    [relation_rows],
    4,
    second_live,
  )
  assert_eq(
    local_managed_test_rows(first_ops),
    if relation_variant == "derive" {
      values_rows
    } else {
      relation_rows
    },
  )
  let expected_second = if relation_variant == "take" {
    ["{\"label\":\"none\",\"id\":null}"]
  } else if assertion ||
    unique ||
    relation_variant == "select" ||
    relation_variant == "distinct" ||
    relation_variant == "derive" {
    ["{\"label\":\"none\",\"id\":null}", "{\"label\":\"one\",\"id\":1}"]
  } else {
    ["{\"label\":\"one\",\"id\":1}"]
  }
  assert_eq(local_managed_test_rows(second_ops), expected_second)
  first_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (first_ops.close)()
  ignore((first_ops.cleanup_refresh)())
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(relation_output))
  second_live.val = false
  relation_live.val = false
  values_live.val = false
  for
    (task, operations) in [(4, second_ops), (2, relation_ops), (1, values_ops)] {
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
test "standard Host splits zero-input values from Relation filter" {
  run_standard_host_values_relation_step(false)
}

///|
test "standard Host splits zero-input values from Relation assertion" {
  run_standard_host_values_relation_step(true)
}

///|
test "standard Host splits zero-input values from unique assertion" {
  run_standard_host_values_relation_step(false, unique=true)
}

///|
test "standard Host splits zero-input values from select" {
  run_standard_host_values_relation_step(false, relation_variant="select")
}

///|
test "standard Host splits zero-input values from take" {
  run_standard_host_values_relation_step(false, relation_variant="take")
}

///|
test "standard Host splits zero-input values from derive" {
  run_standard_host_values_relation_step(false, relation_variant="derive")
}

///|
test "standard Host splits zero-input values from distinct" {
  run_standard_host_values_relation_step(false, relation_variant="distinct")
}

///|
test "standard Host executes independent bounded Relation branches" {
  let (run, issuer) = captured_graph_fixture(
    local_values_two_consumer_chain=true,
    local_values_two_consumer_relation_variant="independent_branches",
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 300000L,
      retained_bytes: 128000000L,
      execution_bytes: 134217728L,
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
  let live = Array::makei(6, _ => Ref(true))
  let operations = []
  let outputs = []
  let rows = []
  for task in 1..<7 {
    let inputs = if task == 2 {
      [outputs[0]]
    } else if task == 4 {
      [outputs[2]]
    } else if task == 5 {
      [outputs[1]]
    } else if task == 6 {
      [outputs[3]]
    } else {
      []
    }
    let input_rows = if task == 2 {
      [rows[0]]
    } else if task == 4 {
      [rows[2]]
    } else if task == 5 {
      [rows[1]]
    } else if task == 6 {
      [rows[3]]
    } else {
      []
    }
    let (ops, output) = run_local_managed_test_task(
      installed,
      run,
      task,
      inputs,
      input_rows,
      task,
      live[task - 1],
      execution_quantum=1,
      require_provider=true,
    )
    operations.push(ops)
    outputs.push(output)
    rows.push(local_managed_test_rows(ops))
  }
  assert_eq(rows[1], ["{\"id\":1,\"label\":\"one\"}"])
  assert_eq(rows[3], ["{\"id\":3,\"label\":\"three\"}"])
  assert_eq(rows[4], rows[1])
  assert_eq(rows[5], ["{\"label\":\"three\",\"id\":3}"])
  live[4].val = false
  @strategy.close_captured_task_output(run, 5)
  (operations[4].close)()
  ignore((operations[4].cleanup_refresh)())
  assert_true(@execution.managed_completed_output_available(outputs[5]))
  assert_true(@execution.managed_completed_output_available(outputs[1]))
  for task in [6, 4, 3, 2, 1] {
    live[task - 1].val = false
    @strategy.close_captured_task_output(run, task)
    (operations[task - 1].close)()
    ignore((operations[task - 1].cleanup_refresh)())
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
fn local_supplied_relation_program(variant : String) -> String {
  if variant == "nested" {
    let nested =
      #|{"version":"actql/0.1","id":"supplied-nested","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"rows","inputs":{"x":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false},"items":{"type":"array","nullable":false,"items":{"type":"number","nullable":false}}}}},"from":"x","steps":[{"sort":[{"id":"asc"}],"as":"ordered"},{"from":"ordered","select":["id","items"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","items"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"rows","result":"r"}}},"steps":[{"select":["id","items"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","items"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"rows","result":"r"}}},"steps":[{"select":["id","items"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","items"]}}}],"results":{"out":{"from":{"stage":"consumer_a","result":"r"}}}}
    return nested.replace(
      old="\"steps\":[{\"sort\"",
      new="\"steps\":[{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"unique\"},{\"from\":\"unique\",\"sort\"",
    )
  }
  guard variant == "baseline" else {
    abort("unknown supplied Relation fixture")
  }
  let program =
    #|{"version":"actql/0.1","id":"supplied-relation","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"rows","inputs":{"x":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}}}},"from":"x","steps":[{"filter":"id > 0","as":"positive"},{"from":"positive","sort":[{"id":"desc"}],"as":"ordered"},{"from":"ordered","take":1,"as":"out"}],"results":{"r":{"from":"out","fields":["id","label"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"rows","result":"r"}}},"steps":[{"select":["id","label"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","label"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"rows","result":"r"}}},"steps":[{"select":["label","id"],"as":"out"}],"results":{"r":{"from":"out","fields":["label","id"]}}}],"results":{"out":{"from":{"stage":"consumer_a","result":"r"}}}}
  program.replace(
    old="{\"filter\":\"id > 0\",\"as\":\"positive\"},{\"from\":\"positive\",\"sort\"",
    new="{\"filter\":\"id > 0\",\"as\":\"positive\"},{\"from\":\"positive\",\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"unique\"},{\"from\":\"unique\",\"sort\"",
  )
}

///|
fn run_standard_host_values_sort_take(
  separate_stage : Bool,
  filter_first : Bool,
  filter_stage : Bool,
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
    local_values_two_consumer_chain=true,
    local_values_two_consumer_sort_take=!separate_stage,
    local_values_two_consumer_relation_variant=if filter_stage {
      "chained_filter_sort_take"
    } else if filter_first {
      "separate_filter_sort_take"
    } else if separate_stage {
      "separate_sort_take"
    } else {
      ""
    },
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
  let held = []
  let operations = []
  let live = []
  let advances = []
  let prefix_tasks = if filter_first || filter_stage { 4 } else { 3 }
  let total_tasks = prefix_tasks + 2
  for task in 1..<(total_tasks + 1) {
    let task_live = Ref(true)
    let task_advances = Ref(0)
    let input = if task == 1 {
      []
    } else if task <= prefix_tasks {
      [held[task - 2]]
    } else {
      [held[prefix_tasks - 1]]
    }
    let input_rows = if task == 1 {
      []
    } else if task <= prefix_tasks {
      [local_managed_test_rows(operations[task - 2])]
    } else {
      [local_managed_test_rows(operations[prefix_tasks - 1])]
    }
    let (task_ops, output) = run_local_managed_test_task(
      installed,
      run,
      task,
      input,
      input_rows,
      task,
      task_live,
      execution_quantum=1,
      execution_advances=Some(task_advances),
    )
    held.push(output)
    operations.push(task_ops)
    live.push(task_live)
    advances.push(task_advances.val)
  }
  assert_true(advances[0] > 1)
  assert_true(advances[1] > 1)
  assert_true(advances[2] > 1)
  let sort_index = if filter_first || filter_stage { 2 } else { 1 }
  let take_index = if filter_first || filter_stage { 3 } else { 2 }
  let consumer_a_index = prefix_tasks
  let consumer_b_index = prefix_tasks + 1
  assert_eq(local_managed_test_rows(operations[sort_index]), [
    "{\"id\":1,\"label\":\"one\"}", "{\"id\":null,\"label\":\"none\"}",
  ])
  assert_eq(local_managed_test_rows(operations[take_index]), [
    "{\"id\":1,\"label\":\"one\"}",
  ])
  assert_eq(local_managed_test_rows(operations[consumer_a_index]), [
    "{\"id\":1,\"label\":\"one\"}",
  ])
  assert_eq(local_managed_test_rows(operations[consumer_b_index]), [
    "{\"label\":\"one\",\"id\":1}",
  ])
  live[consumer_a_index].val = false
  @strategy.close_captured_task_output(run, prefix_tasks + 1)
  (operations[consumer_a_index].close)()
  ignore((operations[consumer_a_index].cleanup_refresh)())
  assert_false(
    @execution.managed_completed_output_available(held[consumer_a_index]),
  )
  assert_true(
    @execution.managed_completed_output_available(held[consumer_b_index]),
  )
  assert_true(@execution.managed_completed_output_available(held[take_index]))
  let remaining_tasks = if filter_first || filter_stage {
    [6, 4, 3, 2, 1]
  } else {
    [5, 3, 2, 1]
  }
  for task in remaining_tasks {
    live[task - 1].val = false
    @strategy.close_captured_task_output(run, task)
    (operations[task - 1].close)()
    ignore((operations[task - 1].cleanup_refresh)())
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
test "standard Host splits zero-input values from sort and take" {
  run_standard_host_values_sort_take(false, false, false)
}

///|
test "standard Host splits an indexed Relation Stage for two consumers" {
  run_standard_host_values_sort_take(true, false, false)
}

///|
test "standard Host splits a unary Relation Stage for two consumers" {
  run_standard_host_values_sort_take(true, true, false)
}

///|
test "standard Host splits a chain of bounded Relation Stages" {
  run_standard_host_values_sort_take(true, false, true)
}

///|
test "standard Host bounds supplied Relation chains and retains two consumers" {
  let (run, issuer) = captured_graph_fixture(
    local_supplied_relation_chain=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 134217728L,
      execution_bytes: 536870912L,
    }),
    supplied_local_rows=[
      (
        1,
        0,
        [
          "{\"id\":2,\"label\":\"two\"}", "{\"id\":1,\"label\":\"one\"}", "{\"id\":0,\"label\":\"zero\"}",
        ],
      ),
    ],
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
  let held = []
  let operations = []
  let live = []
  for task in 1..<7 {
    let task_live = Ref(true)
    let source = if task <= 4 { task - 2 } else { 3 }
    let inputs = if task == 1 { [] } else { [held[source]] }
    let rows = if task == 1 {
      []
    } else {
      [local_managed_test_rows(operations[source])]
    }
    let (task_ops, output) = run_local_managed_test_task(
      installed,
      run,
      task,
      inputs,
      rows,
      task,
      task_live,
      execution_quantum=1,
      require_provider=true,
    )
    held.push(output)
    operations.push(task_ops)
    live.push(task_live)
  }
  assert_eq(local_managed_test_rows(operations[3]), [
    "{\"id\":2,\"label\":\"two\"}",
  ])
  assert_eq(local_managed_test_rows(operations[4]), [
    "{\"id\":2,\"label\":\"two\"}",
  ])
  assert_eq(local_managed_test_rows(operations[5]), [
    "{\"label\":\"two\",\"id\":2}",
  ])
  live[4].val = false
  @strategy.close_captured_task_output(run, 5)
  (operations[4].close)()
  ignore((operations[4].cleanup_refresh)())
  assert_false(@execution.managed_completed_output_available(held[4]))
  assert_true(@execution.managed_completed_output_available(held[5]))
  assert_true(@execution.managed_completed_output_available(held[3]))
  for task in [6, 4, 3, 2, 1] {
    live[task - 1].val = false
    @strategy.close_captured_task_output(run, task)
    (operations[task - 1].close)()
    ignore((operations[task - 1].cleanup_refresh)())
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
test "standard Host retains two consumers of an admitted nested projection" {
  let items = "[" + Array::make(16, "1").join(",") + "]"
  let expected = "{\"id\":1,\"items\":" + items + "}"
  let (run, issuer) = captured_graph_fixture(
    local_supplied_relation_chain=true,
    local_supplied_relation_variant="nested",
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 134217728L,
      execution_bytes: 536870912L,
    }),
    supplied_local_rows=[(1, 0, [expected])],
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
        max_bytes: 2048,
        max_nodes: 512,
      },
      row: {
        max_bytes: 2048,
        max_nodes: 512,
        max_depth: 10,
        max_text_bytes: 2048,
      },
      max_batch_bytes: 2048,
    },
    None,
  ).unwrap()
  let task_count = @strategy.graph_task_count(@strategy.captured_dag_graph(run))
  assert_true(task_count >= 4)
  let operations : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
  let outputs : Array[@execution.ManagedCompletedOutput[Int]] = []
  let lives : Array[Ref[Bool]] = []
  for task in 1..<task_count {
    let producers = @strategy.captured_next_managed_producers(run)
    let inputs = producers
      .filter(producer => producer >= 0)
      .map(producer => outputs[producer - 1])
    let rows = producers
      .filter(producer => producer >= 0)
      .map(producer => local_managed_test_rows(operations[producer - 1]))
    let live = Ref(true)
    let (task_ops, output) = run_local_managed_test_task(
      installed,
      run,
      task,
      inputs,
      rows,
      task,
      live,
      execution_quantum=1,
      require_provider=true,
    )
    assert_eq(local_managed_test_rows(task_ops), [expected])
    operations.push(task_ops)
    outputs.push(output)
    lives.push(live)
  }
  let first_task = task_count - 2
  let second_task = task_count - 1
  lives[first_task - 1].val = false
  @strategy.close_captured_task_output(run, first_task)
  (operations[first_task - 1].close)()
  ignore((operations[first_task - 1].cleanup_refresh)())
  assert_false(
    @execution.managed_completed_output_available(outputs[first_task - 1]),
  )
  assert_true(
    @execution.managed_completed_output_available(outputs[second_task - 1]),
  )
  assert_true(@execution.managed_completed_output_available(outputs[0]))
  for offset in 0..<(task_count - 1) {
    let task = task_count - 1 - offset
    if task != first_task {
      lives[task - 1].val = false
      @strategy.close_captured_task_output(run, task)
      (operations[task - 1].close)()
      ignore((operations[task - 1].cleanup_refresh)())
    }
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
test "standard Host cancels a nested supplied projection after work begins" {
  let items = "[" + Array::make(256, "1").join(",") + "]"
  let (run, issuer) = captured_graph_fixture(
    local_supplied_relation_chain=true,
    local_supplied_relation_variant="nested",
    supplied_local_rows=[(1, 0, ["{\"id\":1,\"items\":" + items + "}"])],
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
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 4096,
        max_nodes: 1024,
      },
      row: {
        max_bytes: 4096,
        max_nodes: 1024,
        max_depth: 10,
        max_text_bytes: 4096,
      },
      max_batch_bytes: 4096,
    },
    None,
  ).unwrap()
  let operations = start_local_managed_test_task_operations(
    installed,
    run,
    1,
    [],
    [],
    require_provider=true,
  )
  for _ in 0..<32 {
    let observation = (operations.advance)(1).unwrap()
    assert_false(observation.complete)
    assert_eq(observation.work, 1L)
  }
  assert_true((operations.request_cancel)())
  assert_true((operations.advance)(1) is Err(_))
  assert_true((operations.execution_stopped)())
  assert_true((operations.output_row)(0) is Err(_))
  (operations.settle)().unwrap()
  assert_true((operations.cleanup_refresh)())
  @strategy.stop_captured_dag(run)
  let task_count = @strategy.graph_task_count(@strategy.captured_dag_graph(run))
  for task in 0..<task_count {
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
test "standard Host stops supplied Relation evaluation after work begins" {
  let (run, issuer) = captured_graph_fixture(
    local_supplied_relation_chain=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 134217728L,
      execution_bytes: 536870912L,
    }),
    supplied_local_rows=[(1, 0, ["{\"id\":2,\"label\":\"two\"}"])],
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
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap()
  let setup = @local_driver.prepare_local_managed_dispatch(
      installed,
      [],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  assert_true(@local_driver.local_managed_dispatch_uses_provider(setup))
  let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  assert_eq(operations.inputs.length(), 0)
  let first = (operations.advance)(1).unwrap()
  assert_false(first.complete)
  assert_eq(first.work, 1L)
  assert_true((operations.request_cancel)())
  assert_true((operations.advance)(1) is Err(_))
  assert_true((operations.execution_stopped)())
  assert_true((operations.output_row)(0) is Err(_))
  assert_true(
    (operations.complete)(1, operations.storage_bytes, fn() { true }) is Err(_),
  )
  (operations.settle)().unwrap()
  (operations.cleanup_refresh)() |> ignore
  assert_false(@strategy.captured_task_completed(run, 1))
  @strategy.stop_captured_dag(run)
  for task in 0..<7 {
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
