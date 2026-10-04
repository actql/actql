///|
test "Carrier work charges discovery even without expansion" {
  let program = query_checked_program_fixture()
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    1,
    10000,
  ).unwrap()
  assert_true(
    @strategy.expand_internal_carrier_tasks(graph, 0, 0) is Err(WorkLimit),
  )
  let same = @strategy.expand_internal_carrier_tasks(graph, 0, 1).unwrap()
  assert_true(physical_equal(same, graph))
  assert_true(
    @strategy.expand_internal_carrier_tasks(graph, 0, -1) is Err(InvalidLimits),
  )
}

///|
fn carrier_work_program() -> @program_check.CheckedProgram raise {
  query_checked_program_fixture(
    program_text=Some(
      (
        #|{"version":"actql/0.1","id":"carrier-work","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"b","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"select":["id"],"as":"out"}],"results":{"seed":{"from":"seed","fields":["id"]},"r":{"from":"out","fields":["id"]}}}],"results":{"seed":{"from":{"stage":"b","result":"seed"}},"out":{"from":{"stage":"b","result":"r"}}}}
      ),
    ),
  )
}

///|
test "Carrier work bounds no-expansion classification and predecessor scans" {
  let program = query_checked_program_fixture(linear_compute_stages=1)
  let graph = @strategy.prepare_checked_dag(
    program,
    physical_graph_owners(program),
    2,
    10000,
  ).unwrap()
  // Two stage visits, one Result, two Steps and two ports, one predecessor
  // edge, the source Stage and its two Steps, its missing predecessor scan,
  // then one suffix Step: 13 entries, despite there being nothing to split.
  for work in [0, 3, 8, 10, 11, 12] {
    assert_true(
      @strategy.expand_internal_carrier_tasks(graph, 0, work) is Err(WorkLimit),
    )
  }
  let same = @strategy.expand_internal_carrier_tasks(graph, 0, 13).unwrap()
  assert_true(physical_equal(same, graph))
}

///|
test "Carrier work bounds classification before task mapping" {
  let program = carrier_work_program()
  let owners = physical_graph_owners(program)
  // Retain the original low budgets; 11..17 stop during classification,
  // and 18/19 stop during task mapping after the newly charged inventory.
  for work in [11, 12, 14, 15, 16, 17, 18, 19] {
    assert_true(
      @strategy.prepare_checked_dag(program, owners, 3, work) is Err(WorkLimit),
    )
  }
}

///|
test "Carrier work bounds edge control and operation remapping" {
  let program = carrier_work_program()
  let owners = physical_graph_owners(program)
  // Original low budgets stay refusal cases. Mapping ends at 23, data
  // reconstruction at 28, control at 29, and operation remapping at 32.
  for work in [20, 23, 24, 25, 26, 27, 28, 29, 30, 31] {
    assert_true(
      @strategy.prepare_checked_dag(program, owners, 3, work) is Err(WorkLimit),
    )
  }
}

///|
test "Carrier work bounds Result remapping and preserves the exact task shape" {
  let program = carrier_work_program()
  let owners = physical_graph_owners(program)
  // Original graph: two Stage validations, one incoming requirement, one
  // gate, one predecessor comparison, one input-completeness visit, two
  // owner snapshots, one Values obligation and two root Result bindings.
  // These are 11 entries; the former 8 omitted the obligation and bindings.
  // Classification costs 7:
  // two stages, two Results, two Steps and one port. Cache it once.
  // Mapping costs 5 (two stages and three tasks), edge reconstruction 5
  // (two stages, two selected Steps and one port), control remapping 1,
  // operation remapping 3 (two stages and the Values requirement), Results 2.
  // Total: 34. Keep the former 31-unit success budget as a refusal; 33
  // stops before the second Result remap, and 34 preserves the same graph.
  for work in [29, 30, 31, 32, 33] {
    assert_true(
      @strategy.prepare_checked_dag(program, owners, 3, work) is Err(WorkLimit),
    )
  }
  let graph = @strategy.prepare_checked_dag(program, owners, 3, 34).unwrap()
  assert_true(physical_equal(@strategy.graph_program(graph), program))
  assert_eq(@strategy.graph_task_count(graph), 3)
  assert_eq(@strategy.graph_task_selected_step(graph, 0), None)
  assert_eq(@strategy.graph_task_selected_step(graph, 1), Some(0))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(1))
  assert_eq(@strategy.graph_task_operation_count(graph, 0), Some(0))
  assert_eq(@strategy.graph_task_operation_count(graph, 1), Some(1))
  assert_eq(@strategy.graph_task_operation_count(graph, 2), Some(0))
  for task in 0..<3 {
    assert_eq(@strategy.graph_task_prefix_end(graph, task), None)
    assert_eq(
      @strategy.graph_task_numeric_observation_count(graph, task),
      Some(0),
    )
    assert_true(
      physical_equal(
        @strategy.graph_task_owner(graph, task).unwrap(),
        owners[if task == 0 { 0 } else { 1 }],
      ),
    )
  }
  assert_eq(@strategy.graph_data_count(graph), 1)
  let edge = @strategy.graph_data_at(graph, 0).unwrap()
  assert_eq((edge.producer, edge.consumer, edge.input), (1, 2, 0))
  assert_eq(edge.target, @pipeline.Step(0))
  assert_eq(edge.operation_input, Some((1, 0)))
  assert_eq(@strategy.graph_control_count(graph), 1)
  let control = @strategy.graph_control_at(graph, 0).unwrap()
  assert_eq((control.predecessor, control.consumer), (0, 1))
  assert_eq(@strategy.graph_result_count(graph), 2)
  for index in 0..<2 {
    match @strategy.graph_result_name(graph, index).unwrap() {
      "out" => assert_eq(@strategy.graph_result_task(graph, index), Some(2))
      "seed" => assert_eq(@strategy.graph_result_task(graph, index), Some(1))
      _ => fail("unexpected Result name")
    }
  }
  // Already-owned tasks still ignore a lower task ceiling. Work actually
  // performed is bounded: exactly three cheap stage-classification visits.
  assert_true(
    @strategy.expand_internal_carrier_tasks(graph, 0, 2) is Err(WorkLimit),
  )
  assert_true(
    physical_equal(
      @strategy.expand_internal_carrier_tasks(graph, 0, 3).unwrap(),
      graph,
    ),
  )
  assert_true(
    @strategy.prepare_checked_dag(program, owners, 2, 10000) is Err(TaskLimit),
  )
}
