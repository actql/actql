///|
fn project_metadata_fixture(wire : String) -> StoredProjectConfiguration? {
  guard @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 262144,
      max_nodes: 8192,
      max_depth: 16,
    })
    is Ok(source) &&
    @decode.admit(source, {
      max_nodes: 8192,
      max_depth: 16,
      max_string_bytes: 131072,
      max_total_string_bytes: 262144,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, ["configuration", "profile"]) is Ok(object) else {
    return None
  }
  prepare_original_project_configuration(object)
}

///|
test "project configuration metadata preserves explicit original absence" {
  let original = project_metadata_fixture(
    "{\"configuration\":null,\"profile\":null}",
  ).unwrap()
  assert_eq(
    original_project_configuration_body(original),
    Some(
      b"{\"connectors\":null,\"lock\":null,\"mock_answers\":[],\"mock_data\":null,\"model_tasks\":null,\"profile\":null,\"state_dir\":\"./.actql\"}",
    ),
  )
}

///|
test "project configuration metadata uses same typed override and ordered mock locators" {
  let original = project_metadata_fixture(
    (
      #|{"configuration":"{\"version\":\"actql-config/0.1\",\"connectors\":\"./connectors.json\",\"model_tasks\":\"./tasks.json\",\"lock\":\"./lock.json\",\"state_dir\":\"./state\",\"profile\":\"production\",\"mock\":{\"data\":\"./data.json\",\"answers\":{\"task:z\":\"./z.yaml\",\"task:a\":\"./a.yaml\"}}}","profile":"mock"}
    ),
  ).unwrap()
  assert_eq(
    original_project_configuration_body(original),
    Some(
      b"{\"connectors\":\"./connectors.json\",\"lock\":\"./lock.json\",\"mock_answers\":[[\"task:z\",\"./z.yaml\"],[\"task:a\",\"./a.yaml\"]],\"mock_data\":\"./data.json\",\"model_tasks\":\"./tasks.json\",\"profile\":\"mock\",\"state_dir\":\"./state\"}",
    ),
  )
  let production = { ..original, requested: Some("production"), }
  assert_true(original_project_configuration_body(production) is None)
}

///|
test "project configuration metadata refuses invalid retired and equal foreign originals" {
  for
    wire in [
      "{\"configuration\":null,\"profile\":\"\"}", "{\"configuration\":null,\"profile\":null,\"account\":\"foreign\"}",
      "{\"configuration\":\"{\\\"version\\\":\\\"actql-config/0.1\\\",\\\"profile\\\":null}\",\"profile\":null}",
      "{\"configuration\":\"{\\\"version\\\":\\\"actql-config/0.1\\\",\\\"version\\\":\\\"actql-config/0.1\\\"}\",\"profile\":null}",
    ] {
    assert_true(project_metadata_fixture(wire) is None)
  }
  let original = project_metadata_fixture(
    "{\"configuration\":\"{\\\"version\\\":\\\"actql-config/0.1\\\"}\",\"profile\":null}",
  ).unwrap()
  let foreign = @host.admit_client_project_configuration(
    "{\"version\":\"actql-config/0.1\"}",
  ).unwrap()
  assert_true(
    original_project_configuration_body({
      ..original,
      configuration: Some(foreign),
    })
    is None,
  )
  @host.retire_client_project_profile(original.selection).unwrap()
  assert_true(original_project_configuration_body(original) is None)
}
