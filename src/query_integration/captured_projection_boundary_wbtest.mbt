///|
test "captured projection consumes the acquisition port before publishing its later Result" {
  // Independent machine Program: acquisition completes Step 1, while the
  // imported Stage Result belongs to Step 3. Neither port can stand for the other.
  let document =
    #|{"version":"actql/0.1","id":"captured-projection","stages":[{"id":"capture","inputs":{"records":{"connector":"crm/main","resource":"r"}},"steps":[{"from":"records","filter":{"literal":true}},{"select":["id"],"as":"captured"},{"from":"captured","derive":{"value":"id + 10"},"as":"derived"},{"from":"derived","select":["id","value"],"as":"projected"}],"results":{"source":{"from":"projected","fields":["id","value"]}}},{"id":"main","inputs":{"records":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"records","sort":[{"id":"asc"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["id","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let checked = acquired_relation_branch_checked(document)
  let (run, issuer) = captured_graph_fixture(
    checked_program=Some(checked),
    rows=Some(["{\"id\":3}", "{\"id\":1}", "{\"id\":2}"]),
    parameter_json="{}",
    query_prefix_end=Some(1),
  )
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_task_count(graph), 4)
  assert_eq(@strategy.graph_task_prefix_end(graph, 0), Some(1))
  assert_eq(@strategy.graph_task_target(graph, 0), Some(@pipeline.Step(1)))
  assert_eq(@strategy.graph_task_selected_step(graph, 1), Some(2))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(3))
  assert_eq(
    @strategy.graph_stage_target_task(graph, 0, @pipeline.Step(3)),
    Some(2),
  )
  let edge = @strategy.graph_data_at(graph, 0).unwrap()
  assert_eq(
    (edge.producer, edge.consumer, edge.target),
    (0, 1, @pipeline.Step(1)),
  )
  assert_eq(@strategy.data_edge_operation_input(edge), Some((2, 0)))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
  let input = @strategy.captured_task_input(run, 1, 100, 10000).unwrap()
  assert_eq(@execution.producer_read_row_count(input), 3)
  assert_true(@execution.producer_read_available(input))
  @mock.close_mock_query_issuer(issuer)
  assert_false(@execution.producer_read_available(input))
  @strategy.stop_captured_dag(run)
  for task in 0..<@strategy.graph_task_count(graph) {
    @strategy.close_captured_task_output(run, task)
  }
}
