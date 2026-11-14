///|
fn project_geometry_zero_array(count : Int) -> String {
  let body = StringBuilder()
  body.write_string("[")
  for index in 0..<count {
    if index > 0 { body.write_string(",") }
    body.write_string("0")
  }
  body.write_string("]")
  body.to_string()
}

///|
fn project_geometry_locators(count : Int) -> String {
  let body = StringBuilder()
  body.write_string("{")
  for index in 0..<count {
    if index > 0 { body.write_string(",") }
    body.write_string("\"original-" + index.to_string() + "\":\"./original.yaml\"")
  }
  body.write_string("}")
  body.to_string()
}

///|
test "Project original geometry keeps connection spans above the former node ceiling" {
  let entry = "{ \"connector\" : \"future\", \"original\" : " +
    project_geometry_zero_array(4100) + " }"
  let wire = "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"selected\":" + entry + "}}"
  assert_true(wire.length() < 65536)
  let selected = admit_client_project_connections(wire).unwrap()
  assert_eq(selected.original_wire(), wire)
  assert_eq(selected.count(), 1)
  assert_eq(selected.at(0), Some(("selected", "future", entry)))
  assert_eq(selected.at(1), None)
}

///|
test "Project original geometry keeps catalog spans above the former node ceiling" {
  let entry = "{ \"unselected\" : " + project_geometry_zero_array(4100) + " }"
  let wire = "{\"connections\":{\"original\":" + entry + "}}"
  assert_true(wire.length() < 65536)
  let selected = admit_client_project_catalog(wire).unwrap()
  assert_eq(selected.original_wire(), wire)
  assert_eq(selected.count(), 1)
  assert_eq(selected.at(0), Some(("original", entry)))
  assert_eq(selected.at(1), None)
}

///|
test "Project original geometry retains every configuration answer past the former wire ceiling" {
  let wire = "{\"version\":\"actql-config/0.1\",\"mock\":{\"answers\":" +
    project_geometry_locators(5000) + "}}"
  assert_true(wire.length() > 65536)
  let selected = admit_client_project_configuration(wire).unwrap()
  assert_eq(selected.mock_answer_count(), 5000)
  assert_eq(selected.mock_answer_at(0), Some(("original-0", "./original.yaml")))
  assert_eq(selected.mock_answer_at(4999), Some(("original-4999", "./original.yaml")))
  assert_eq(selected.mock_answer_at(5000), None)
}

///|
test "Project original geometry retains every model task past the former wire ceiling" {
  let wire = "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":" +
    project_geometry_locators(5000) + ",\"providers\":{}}"
  assert_true(wire.length() > 65536)
  let selected = admit_client_project_model_registry(wire).unwrap()
  assert_eq(selected.original_wire(), wire)
  assert_eq(selected.task_count(), 5000)
  assert_eq(selected.task_at(0), Some(("original-0", "./original.yaml")))
  assert_eq(selected.task_at(4999), Some(("original-4999", "./original.yaml")))
  assert_eq(selected.task_at(5000), None)
  assert_eq(selected.provider_count(), 0)
}

///|
test "Project original geometry admits complete empty declarations past the former wire ceiling" {
  let padding = " ".repeat(65537)
  let selected = admit_client_source_free_project_bindings(
    Some("{\"version\":\"actql-connectors/0.1\",\"connections\":{}}" + padding),
    Some("{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{}}" + padding),
  ).unwrap()
  assert_true(selected.has_connectors_file())
  assert_true(selected.has_model_tasks_file())
}
