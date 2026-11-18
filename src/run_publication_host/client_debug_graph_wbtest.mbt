///|
fn debug_graph_stage_owners(
  prepared : PreparedClientProgram,
) -> Array[@lower.BoundPrepared] {
  let graph = prepared_client_graph(prepared)
  let checked = @strategy.graph_program(graph)
  let owners = []
  for stage in 0..<@checked.unit_count(checked) {
    let pipeline = @checked.unit_pipeline(checked, stage).unwrap()
    let task = if @pipeline.step_count(pipeline) > 0 {
      @strategy.graph_stage_operation_task(graph, stage, 0).unwrap()
    } else {
      // This fixture's input-only Stage retains its first original port.
      @strategy.graph_stage_target_task(graph, stage, @pipeline.Input(0)).unwrap()
    }
    owners.push(@strategy.graph_task_owner(graph, task).unwrap())
  }
  owners
}

///|
let debug_graph_chain_document : String =
  #|{"version":"actql/0.1","id":"debug-original-chain","stages":[{"id":"main","inputs":{},"steps":[{"as":"original","values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]}},{"from":"original","filter":"id > 1","as":"filtered"},{"from":"filtered","select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}

///|
test "Debug prepares real selected operations before work while Normal remains fused" {
  let prepared = input_result_prepared(debug_graph_chain_document)
  let normal = prepared_client_graph(prepared)
  let owners = debug_graph_stage_owners(prepared)
  let checked = @strategy.graph_program(normal)
  let debug = @strategy.prepare_checked_debug_dag(
    checked,
    owners,
    16,
    100000,
    source_free_root=true,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(normal), 1)
  assert_eq(@strategy.graph_task_count(debug), 3)
  assert_true(physical_equal(@strategy.graph_program(debug), checked))
  for step in 0..<3 {
    assert_eq(@strategy.graph_task_selected_step(debug, step), Some(step))
    assert_eq(
      @strategy.graph_task_target(debug, step),
      Some(@pipeline.Step(step)),
    )
    assert_true(
      physical_equal(
        @strategy.graph_task_owner(debug, step).unwrap(),
        owners[0],
      ),
    )
    assert_eq(@strategy.graph_stage_operation_task(debug, 0, step), Some(step))
  }
  assert_eq(@strategy.graph_data_count(debug), 2)
  assert_true(@strategy.graph_ordered_inputs_complete(debug))
  let old = @strategy.graph_result_occurrence(normal, 0).unwrap()
  let next = @strategy.graph_result_occurrence(debug, 0).unwrap()
  // These are two before-compilation candidates, not an existing Run replan.
  // The ordinary constructor issues each candidate's private occurrence; both
  // retain the SAME checked public ResultPort and lower owner through remap.
  assert_true(
    physical_equal(
      @execution.managed_result_occurrence_port(old),
      @execution.managed_result_occurrence_port(next),
    ),
  )
  assert_true(
    physical_equal(
      @execution.managed_result_occurrence_owner(old),
      @execution.managed_result_occurrence_owner(next),
    ),
  )
  assert_eq(@execution.managed_result_occurrence_name(next), "answer")
}

///|
test "Debug keeps original repeated peer ports and effective parameter owners" {
  let prepared = structural_explanation_prepared(
    "{\"gt\":[{\"field\":\"id\"},{\"$param\":\"threshold\"}]}",
    parameter=true,
  )
  let normal = prepared_client_graph(prepared)
  let owners = debug_graph_stage_owners(prepared)
  let debug = @strategy.prepare_checked_debug_dag(
    @strategy.graph_program(normal),
    owners,
    16,
    100000,
    source_free_root=true,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(debug), 4)
  assert_eq(@strategy.graph_task_input_count(debug, 3), Some(2))
  let mut left = -1
  let mut right = -1
  for index in 0..<@strategy.graph_data_count(debug) {
    let edge = @strategy.graph_data_at(debug, index).unwrap()
    if edge.consumer == 3 && edge.input == 0 {
      left = edge.producer
    }
    if edge.consumer == 3 && edge.input == 1 {
      right = edge.producer
    }
  }
  assert_eq(left, 2)
  assert_eq(right, 0)
  assert_true(@strategy.graph_ordered_inputs_complete(debug))
  for task in 0..<4 {
    assert_true(
      physical_equal(
        @strategy.graph_task_owner(debug, task).unwrap(),
        owners[0],
      ),
    )
  }
  let foreign = structural_explanation_prepared(
    "{\"gt\":[{\"field\":\"id\"},{\"$param\":\"threshold\"}]}",
    parameter=true,
  )
  assert_true(
    @strategy.prepare_checked_debug_dag(
      @strategy.graph_program(normal),
      debug_graph_stage_owners(foreign),
      16,
      100000,
      source_free_root=true,
    )
    is Err(Graph(ForeignPipeline(0))),
  )
}

///|
test "Debug preserves input-only identity and refuses insufficient task or work construction" {
  let input = input_result_prepared(input_result_document)
  let debug = @strategy.prepare_checked_debug_dag(
    @strategy.graph_program(input.graph),
    debug_graph_stage_owners(input),
    16,
    100000,
    source_free_root=true,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(debug), 2)
  assert_eq(@strategy.graph_task_target(debug, 1), Some(@pipeline.Input(0)))
  assert_eq(@strategy.graph_task_selected_step(debug, 1), None)
  let prepared = input_result_prepared(debug_graph_chain_document)
  let checked = @strategy.graph_program(prepared.graph)
  let owners = debug_graph_stage_owners(prepared)
  assert_true(
    @strategy.prepare_checked_debug_dag(
      checked,
      owners,
      2,
      100000,
      source_free_root=true,
    )
    is Err(Graph(TaskLimit)),
  )
  assert_true(
    @strategy.prepare_checked_debug_dag(
      checked,
      owners,
      16,
      0,
      source_free_root=true,
    )
    is Err(Graph(WorkLimit)),
  )
  assert_eq(@strategy.graph_task_count(prepared.graph), 1)
}

///|
test "Debug missing selected provider remains a boundary capability refusal" {
  let prepared = client_composed_infer_test_program()
  assert_true(
    @strategy.prepare_checked_debug_dag(
      @strategy.graph_program(prepared.graph),
      debug_graph_stage_owners(prepared),
      32,
      100000,
      source_free_root=true,
    )
    is Err(BoundaryUnavailable(_, _)),
  )
  // This is checked graph preparation only. No Model constructor/provider,
  // Source, Run, Sample, control operation or execution has been invoked.
}
