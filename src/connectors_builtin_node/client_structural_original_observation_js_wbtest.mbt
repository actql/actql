///|
test "Request structural projection keeps the original malformed Program and parent pointer" {
  let environment = original_lookup_diagnostic_environment(false)
  let wire = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let publication = @source_publication.prepare_published_query_environment(
    environment, wire,
  ).unwrap()
  for
    (document, pointer) in [
      ("{\"version\":\"actql/0.1\",\"id\":\"original\"}", ""),
      (
        "{\"version\":\"actql/0.1\",\"id\":\"original\",\"stages\":[{\"id\":\"s\",\"inputs\":{}}],\"results\":{}}",
        // The native Program index owns no original key-spelling spans. Keep
        // its proven root; do not invent a deeper caller-owned JSON Pointer.
         "",
      ),
    ] {
    let (parent, input) = request_diagnostic_test_parent()
    let original = client_program_prepare_request_native_computation(
      parent,
      input,
      request_diagnostic_test_json(document),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    )
    assert_true(original is Err(Preparation(ProgramJson(Syntax(_)))))
    let project = () => {
      client_program_project_request_check_outcome(
        parent,
        input,
        original,
        wire,
        "ctx:" + "a".repeat(64),
        "program",
        "rev:" + "b".repeat(64),
        document.length(),
        None,
        0,
        None,
        0,
        "corr:" + "c".repeat(32),
        None,
        None,
        None,
      )
    }
    let report = project().unwrap().unwrap()
    assert_true(report.contains("\"verdict\":\"invalid\""))
    assert_true(report.contains("\"code\":\"program_structure_invalid\""))
    assert_true(report.contains("\"issue\":\"missing_field\""))
    assert_true(report.contains("\"document_id\":\"program\""))
    assert_true(report.contains("\"kind\":\"structured\""))
    assert_true(report.contains("\"pointer\":\"" + pointer + "\""))
    assert_true(report.contains("\"revision\":\"rev:" + "b".repeat(64)))
    client_program_abort_request_preparation(parent).unwrap()
    assert_true(project().unwrap() is None)
  }
}

///|
test "Request structural projection refuses a different original failure or Request input" {
  let environment = original_lookup_diagnostic_environment(false)
  let wire = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let publication = @source_publication.prepare_published_query_environment(
    environment, wire,
  ).unwrap()
  let document = "{\"version\":\"actql/0.1\",\"id\":\"original\"}"
  let (parent, input) = request_diagnostic_test_parent()
  let (foreign, other) = request_diagnostic_test_parent()
  let prepare = (parent, input) => {
    client_program_prepare_request_native_computation(
      parent,
      input,
      request_diagnostic_test_json(document),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    )
  }
  let original = prepare(parent, input)
  let other_result = prepare(foreign, other)
  for (supplied_input, result) in [(other, original), (input, other_result)] {
    assert_true(
      client_program_project_request_check_outcome(
        parent,
        supplied_input,
        result,
        wire,
        "ctx:" + "a".repeat(64),
        "program",
        "rev:" + "b".repeat(64),
        document.length(),
        None,
        0,
        None,
        0,
        "corr:" + "c".repeat(32),
        None,
        None,
        None,
      )
      is Err(ForeignOriginal),
    )
  }
  client_program_abort_request_preparation(parent).unwrap()
  client_program_abort_request_preparation(foreign).unwrap()
}
