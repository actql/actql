///|
test "captured row assertion keeps the acquisition and later Result ports distinct" {
  // The Source completes Step 1. The independent key assertion is Step 2;
  // its Stage Result must not borrow the earlier acquisition as completion.
  let document =
    #|{"version":"actql/0.1","id":"captured-assertion","stages":[{"id":"capture","inputs":{"records":{"connector":"crm/main","resource":"r"}},"steps":[{"from":"records","filter":{"literal":true}},{"select":["id"],"as":"captured"},{"from":"captured","assert_rows":{"unique_by":["id"]},"as":"unique_rows"}],"results":{"source":{"from":"unique_rows","fields":["id"]}}},{"id":"main","inputs":{"records":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"records","sort":[{"id":"asc"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let checked = acquired_relation_branch_checked(document)
  let sequence = query_checked_sequence(checked, prefix_end=Some(1))
  let owners = physical_graph_owners(checked)
  owners[0] = @query.query_sequence_owner(sequence)
  let graph = @strategy.prepare_checked_dag(checked, owners, 10, 100000).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 3)
  assert_eq(@strategy.graph_task_prefix_end(graph, 0), Some(1))
  assert_eq(@strategy.graph_task_target(graph, 0), Some(@pipeline.Step(1)))
  assert_eq(@strategy.graph_task_selected_step(graph, 1), Some(2))
  assert_eq(
    @strategy.graph_stage_target_task(graph, 0, @pipeline.Step(2)),
    Some(1),
  )
  let edge = @strategy.graph_data_at(graph, 0).unwrap()
  assert_eq(
    (edge.producer, edge.consumer, edge.target),
    (0, 1, @pipeline.Step(1)),
  )
  assert_eq(@strategy.data_edge_operation_input(edge), Some((2, 0)))
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
}
