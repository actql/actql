///|
// Read-only diagnostic of the checked task/producer boundary. This does not
// loosen the original prefix selector or execute a Content/Model provider.
test "original source-free Content prefix reports the checked selected task and input target" {
  let (prepared, _, _, _) = original_prefix_execution_fixture()
  let graph = @publication_host.prepared_client_graph(prepared)
  let occurrences = @publication_host.prepared_client_serialization_occurrences(
    prepared,
  )
  for (task, step) in occurrences {
    println("Content task=" + task.to_string() + " step=" + step.to_string())
  }
  match @strategy.graph_task_selected_step(graph, 0) {
    Some(step) => println("caller task0 selected=" + step.to_string())
    None => println("caller task0 has no selected step")
  }
  let barrier = @publication_host.prepare_client_serialization(
    prepared,
    0,
    1,
    max_work=10000,
  ).unwrap()
  match
    @pipeline.serialization_order_input(@lower.serialization_order(barrier)) {
    @pipeline.Step(step) =>
      println("Content order input step=" + step.to_string())
    _ => println("Content order input is not a step")
  }
  let prefix = prepare_client_serialization_prefix(
    prepared,
    0,
    1,
    source_query_original_registry,
    source_query_original_values,
    None,
    None,
  )
  println("caller task0 prefix=" + (prefix is Some(_)).to_string())
  assert_eq(occurrences.length(), 1)
}
