///|
let retained_chain_document : String =
  #|{"version":"actql/0.1","id":"retained-three-stage","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > 0","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"middle","inputs":{"x":{"result":{"stage":"acquire","result":"r"}}},"steps":[{"derive":{"n":"id + 10"}},{"select":["n"],"as":"out"}],"results":{"r":{"from":"out","fields":["n"]}}},{"id":"final","inputs":{"x":{"result":{"stage":"middle","result":"r"}}},"steps":[{"derive":{"answer":"n * 2"}},{"select":["answer"],"as":"out"}],"results":{"r":{"from":"out","fields":["answer"]}}}],"results":{"answer":{"from":{"stage":"final","result":"r"}}}}

///|
test "retained projection preserves original consumer producer and control coordinates" {
  let (_, _, _, _, prepared) = resident_source_dispatch_fixture(
    document=retained_chain_document,
  )
  let graph = @host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 3)
  let projection = @strategy.prepare_retained_task_projection(graph, 2).unwrap()
  assert_eq(@strategy.retained_task_projection_producer(projection), 1)
  assert_eq(@strategy.retained_task_projection_consumer(projection), 2)
  let original = @strategy.checked_task_identity(
    @strategy.prepare_checked_task_reference(graph, 2, 32, 1000).unwrap(),
  )
  let projected = @strategy.checked_task_identity(
    @strategy.retained_task_projection_reference(projection, 32, 1000).unwrap(),
  )
  assert_eq(projected, original)
  assert_eq(projected.task, 2)
  assert_eq(projected.output_step, 1)
  assert_eq(projected.inputs.length(), 1)
  assert_eq(projected.inputs[0].input, 0)
  assert_eq(projected.inputs[0].producer, 1)
  assert_false(projected.inputs[0].producer_target_is_input)
  assert_eq(projected.inputs[0].producer_target_index, 1)
  assert_eq(projected.controls, [1])
  assert_eq(@strategy.graph_result_task(graph, 0), Some(2))
  assert_true(@strategy.prepare_retained_task_projection(graph, 0) is Err(_))
  assert_true(@strategy.prepare_retained_task_projection(graph, 3) is Err(_))
}

///|
test "resident source admits a checked three-stage single-input chain" {
  let (admission, request, body, binding, _) = resident_source_dispatch_fixture(
    document=retained_chain_document,
  )
  let materials = admit_materials(
    admission, request, body, binding, "2026-10-06T00:00:00.000Z",
  ).unwrap()
  assert_true(
    resident_source_dispatch_role(materials, request)
    is Ok(InternalSourceProducer),
  )
}

///|
test "resident linear profile refuses legal fanout without changing common graph admission" {
  let document = retained_chain_document
    .replace(
      old="\"stage\":\"middle\",\"result\":\"r\"",
      new="\"stage\":\"acquire\",\"result\":\"r\"",
    )
    .replace(old="\"n * 2\"", new="\"id * 2\"")
  let (_, _, _, _, prepared) = resident_source_dispatch_fixture(document~)
  assert_eq(
    @strategy.graph_task_count(@host.prepared_client_graph(prepared)),
    3,
  )
  assert_false(resident_linear_graph(@host.prepared_client_graph(prepared)))
}
