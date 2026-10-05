///|
fn shared_seed_join_document() -> String {
  // Independent machine Program, not query-compiler output. One Values root
  // reaches two branches through step 2, then exact JOIN ports meet at step 7.
  let document =
    #|{"version":"actql/0.1","id":"shared-seed-join","stages":[{"id":"main","inputs":{},"steps":[{"as":"unit","values":{"schema":{"unit":{"type":"boolean","nullable":false}},"rows":[{"unit":true}]}},{"from":"unit","derive":{"key":{"literal":1}},"as":"keyed"},{"from":"keyed","select":[{"id":"key"}],"as":"seed"},{"from":"seed","derive":{"left_score":{"literal":10}},"as":"left_derived"},{"from":"left_derived","select":["id","left_score"],"as":"left"},{"from":"seed","derive":{"right_score":{"literal":20}},"as":"right_derived"},{"from":"right_derived","select":["id","right_score"],"as":"right"},{"from":"left","join":{"kind":"inner","with":"right","on":[{"left":"id","right":"id"}],"select":{"joined_score":"left.left_score"},"max_output_rows":1},"as":"joined"},{"from":"joined","derive":{"score":{"field":"joined_score"}},"as":"derived"},{"from":"derived","select":["score"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  document
}

///|
test "shared seed JOIN owns ten exact tasks and both operation ports" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let limits = run_materials_limits()
  let prepared = prepare_effect_free_client_program(
    shared_seed_join_document(),
    Json,
    environment,
    None,
    { ..limits.preparation, max_tasks: 10, },
  ).unwrap()
  let graph = prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 10)
  assert_eq(@strategy.graph_data_count(graph), 10)
  assert_eq(@strategy.graph_captured_prefix(graph), 0)
  let owner = @strategy.graph_task_owner(graph, 0).unwrap()
  let input_counts = [0, 1, 1, 1, 1, 1, 1, 2, 1, 1]
  for task, inputs in input_counts {
    assert_eq(
      @strategy.graph_task_target(graph, task),
      Some(@pipeline.Step(task)),
    )
    assert_eq(@strategy.graph_task_selected_step(graph, task), Some(task))
    assert_eq(@strategy.graph_task_prefix_end(graph, task), None)
    assert_eq(@strategy.graph_task_unit_index(graph, task), Some(0))
    assert_eq(@strategy.graph_task_input_count(graph, task), Some(inputs))
    assert_true(
      physical_equal(owner, @strategy.graph_task_owner(graph, task).unwrap()),
    )
  }
  // Every edge is independently fixed, including the shared producer and
  // both JOIN ports. A remap to the preceding task cannot satisfy this list.
  let expected_edges = [
    (0, 1, 0),
    (1, 2, 0),
    (2, 3, 0),
    (3, 4, 0),
    (2, 5, 0),
    (5, 6, 0),
    (4, 7, 0),
    (6, 7, 1),
    (7, 8, 0),
    (8, 9, 0),
  ]
  for index, expected in expected_edges {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    assert_eq((edge.producer, edge.consumer, edge.input), expected)
    assert_eq(edge.target, @pipeline.Step(expected.0))
    assert_eq(
      @strategy.data_edge_operation_input(edge),
      Some((expected.1, expected.2)),
    )
  }
  assert_eq(@strategy.graph_result_count(graph), 1)
  assert_eq(@strategy.graph_result_name(graph, 0), Some("answer"))
  assert_eq(@strategy.graph_result_task(graph, 0), Some(9))
  let occurrence = @strategy.graph_result_occurrence(graph, 0).unwrap()
  assert_true(
    physical_equal(
      owner,
      @execution.managed_result_occurrence_owner(occurrence),
    ),
  )
  assert_eq(
    @results.port_target(@execution.managed_result_occurrence_port(occurrence)),
    @pipeline.Step(9),
  )
  assert_eq(
    @strategy.graph_program_definition_cid(graph),
    prepared_client_identity(prepared).program_definition_cid,
  )
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(client_task_compilation_result_names(compilation), ["answer"])
  assert_true(
    prepare_effect_free_client_program(
      shared_seed_join_document(),
      Json,
      environment,
      None,
      { ..limits.preparation, max_tasks: 9, },
    )
    is Err(Graph(TaskLimit)),
  )
  let run = open_prepared_source_free_client_run(prepared, {
    planning_work: 100000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 500000L,
    retained_bytes: 200000000L,
    execution_bytes: 536870912L,
  }).unwrap()
  let opened_graph = @strategy.captured_dag_graph(run)
  assert_true(
    @execution.managed_result_occurrence_same(
      occurrence,
      @strategy.graph_result_occurrence(opened_graph, 0).unwrap(),
    ),
  )
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.attempts, 0)
  assert_eq(usage.holdings, 0)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}
