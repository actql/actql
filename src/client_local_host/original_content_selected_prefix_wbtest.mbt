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

///|
test "original typed document Content prefix diagnoses the existing caller Program coordinates" {
  let document =
    #|{"version":"actql/0.1","id":"generated-content-model","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":18}},"as":"attachment"},{"assert_rows":{"unique_by":["name"]},"as":"unique"},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"document":{"field":"content"}}},"as":"inferred"}],"results":{"answer":{"from":"inferred","fields":["name","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"answer"}}}}
  let (prepared, _, _, _) = original_prefix_execution_fixture(
    document_override=Some(document),
    environment_override=Some(source_query_original_environment),
    serialization_bounds=(2, 18),
    model_task_override=Some(original_typed_content_task()),
    model_execution_override=Some(original_typed_content_execution()),
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  match @strategy.graph_task_selected_step(graph, 0) {
    Some(step) => println("typed caller task0 selected=" + step.to_string())
    None => println("typed caller task0 has no selected step")
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
      println("typed Content order input step=" + step.to_string())
    _ => println("typed Content order input is not a step")
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
  println("typed caller task0 prefix=" + (prefix is Some(_)).to_string())
  assert_eq(
    @publication_host.prepared_client_serialization_occurrences(prepared),
    [(0, 1)],
  )
}
