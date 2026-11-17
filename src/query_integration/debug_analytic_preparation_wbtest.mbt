///|
// Only real preparation over the existing independently authored shared-seed
// Programs. No provider activation, compilation, Run or supplied authority.
fn debug_shared_seed_preparation(join : Bool) -> Unit raise {
  let prepared = analytic_shared_seed_prepared(join)
  let normal = @publication_host.prepared_client_graph(prepared)
  let owner = @strategy.graph_task_owner(normal, 0).unwrap()
  let graph = match
    @strategy.prepare_checked_debug_dag(
      @strategy.graph_program(normal),
      [owner],
      8,
      100000,
      source_free_root=true,
    ) {
    Ok(value) => value
    Err(issue) => fail("Original Debug preparation: " + @debug.to_string(issue))
  }
  assert_eq(@strategy.graph_task_count(graph), 8)
  assert_eq(@strategy.graph_data_count(graph), 8)
  for task, inputs in [0, 1, 1, 1, 1, 2, 1, 1] {
    assert_eq(@strategy.graph_task_selected_step(graph, task), Some(task))
    assert_eq(
      @strategy.graph_task_target(graph, task),
      Some(@pipeline.Step(task)),
    )
    assert_eq(@strategy.graph_task_input_count(graph, task), Some(inputs))
    assert_eq(@strategy.graph_stage_operation_task(graph, 0, task), Some(task))
    assert_true(
      physical_equal(@strategy.graph_task_owner(graph, task).unwrap(), owner),
    )
  }
  for
    index, expected in [
      (0, 1, 0),
      (1, 2, 0),
      (0, 3, 0),
      (3, 4, 0),
      (2, 5, 0),
      (4, 5, 1),
      (5, 6, 0),
      (6, 7, 0),
    ] {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    assert_eq((edge.producer, edge.consumer, edge.input), expected)
    assert_eq(edge.target, @pipeline.Step(expected.0))
    assert_eq(
      @strategy.data_edge_operation_input(edge),
      Some((expected.1, expected.2)),
    )
  }
  assert_true(
    @lower.payload(@lower.node_at(@lower.bound_preparation(owner), 6).unwrap())
    is @lower.Analytic(_),
  )
  let prior = @strategy.graph_result_occurrence(normal, 0).unwrap()
  let selected = @strategy.graph_result_occurrence(graph, 0).unwrap()
  assert_true(
    physical_equal(
      @execution.managed_result_occurrence_port(prior),
      @execution.managed_result_occurrence_port(selected),
    ),
  )
  assert_true(
    physical_equal(@execution.managed_result_occurrence_owner(selected), owner),
  )
  assert_eq(@strategy.graph_result_name(graph, 0), Some("answer"))
  assert_eq(@strategy.graph_result_task(graph, 0), Some(7))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}

///|
test "Debug preserves original bounded shared-seed APPEND analytic eligibility and eight ports" {
  debug_shared_seed_preparation(false)
}

///|
test "Debug preserves original bounded shared-seed JOIN analytic eligibility and eight ports" {
  debug_shared_seed_preparation(true)
}

///|
let debug_non_dag_analytic_document : String =
  #|{"version":"actql/0.1","id":"debug-analytic-unary-source","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"amount":{"type":"number","nullable":false}},"rows":[{"id":1,"amount":10}]},"as":"seed"},{"from":"seed","analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"frame":{"start":"unbounded_preceding","end":"current_row"},"functions":{"n":{"fn":"count","field":"amount"}}},"as":"windowed"}],"results":{"rows":{"from":"windowed","fields":["id","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}

///|
test "Debug cannot admit selected analytic without the existing bounded relation-DAG context" {
  let prepared = @publication_host.prepare_effect_free_client_program(
    debug_non_dag_analytic_document,
    Json,
    analytic_shared_seed_environment(),
    None,
    analytic_shared_seed_limits(),
  ).unwrap()
  let normal = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(normal), 1)
  let owner = @strategy.graph_task_owner(normal, 0).unwrap()
  assert_true(
    @strategy.prepare_checked_debug_dag(
      @strategy.graph_program(normal),
      [owner],
      8,
      100000,
      source_free_root=true,
    )
    is Err(BoundaryUnavailable(0, 1)),
  )
}
