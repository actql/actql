///|
fn captured_task_inventory_document(task_count : Int) -> String {
  let stages : Array[String] = [
    (
      #|{"id":"capture","inputs":{"records":{"connector":"crm/main","resource":"r"}},"steps":[{"from":"records","select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}}
    ),
    (
      #|{"id":"main","inputs":{"records":{"result":{"stage":"capture","result":"rows"}}},"steps":[{"from":"records","filter":"id > 1"},{"select":["id"],"as":"selected"},{"from":"records","select":["id"],"as":"complete"},{"from":"complete","group":{"by":[],"aggregates":{"id":{"fn":"count"}}},"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}}
    ),
  ]
  let mut previous = "main"
  for index in 0..<(task_count - 5) {
    let name = "compute\{index}"
    stages.push(
      "{\"id\":\"\{name}\",\"inputs\":{\"r\":{\"result\":{\"stage\":\"\{previous}\",\"result\":\"rows\"}}},\"steps\":[{\"filter\":\"id >= 0\"},{\"select\":[\"id\"],\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"id\"]}}}",
    )
    previous = name
  }
  "{\"version\":\"actql/0.1\",\"id\":\"captured-task-inventory\",\"stages\":[" +
  stages.join(",") +
  "],\"results\":{\"answer\":{\"from\":{\"stage\":\"\{previous}\",\"result\":\"rows\"}}}}"
}

///|
// Checked Source/Compute originals only; no Native File I/O or Run grant.
test "one captured Source retains checked task inventories across thirty two" {
  for count in [31, 32, 33, 35] {
    let prepared = single_installed_prepared(
      document=captured_task_inventory_document(count),
    )
    let graph = @publication_host.prepared_client_graph(prepared)
    assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 1)
    assert_eq(@strategy.graph_captured_prefix(graph), 1)
    assert_eq(@strategy.graph_result_count(graph), 1)
    assert_eq(@strategy.graph_task_count(graph), count)
    assert_false(@strategy.graph_program_has_effects(graph))
    assert_false(@publication_host.prepared_client_uses_graph_carrier(prepared))
    assert_true(
      @publication_host.prepared_client_composed_infer_occurrences(prepared)
      .unwrap()
      .is_empty(),
    )
    assert_true(
      @publication_host.prepared_client_serialization_occurrences(prepared).is_empty(),
    )
  }
}
