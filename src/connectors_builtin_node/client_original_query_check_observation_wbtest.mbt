///|
test "Request projection keeps original syntax and unresolved Query terminals" {
  let environment = original_lookup_diagnostic_environment(false)
  let wire = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let publication = @source_publication.prepare_published_query_environment(
    environment, wire,
  ).unwrap()
  let context = "ctx:" + "a".repeat(64)
  let revision = "rev:" + "b".repeat(64)
  let original_namespace = client_program_check_source_namespace(
    environment,
    wire,
    "queries",
    "sha256:" + "d".repeat(64),
    context,
    revision,
  ).unwrap()
  for
    (text, supplied_namespace, expected) in [
      ("SELECT (", None, "query_syntax_invalid"),
      ("SELECT id FROM missing", None, "unresolved_protected"),
      ("SELECT id FROM missing", Some(original_namespace), "query_alias_absent"),
    ] {
    let (parent, receipt) = request_diagnostic_test_parent()
    let source = "{\"format\":\"sql\",\"text\":\"" + text + "\"}"
    let original = client_program_prepare_request_source_computation(
      parent,
      receipt,
      request_diagnostic_test_json(source),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    )
    assert_true(original is Err(_))
    let report = client_program_project_request_check_outcome(
        parent,
        receipt,
        original,
        wire,
        context,
        "text",
        revision,
        text.length(),
        None,
        0,
        None,
        0,
        "corr:" + "c".repeat(32),
        None,
        supplied_namespace,
      )
      .unwrap()
      .unwrap()
    assert_true(report.contains(expected), msg=report)
    assert_true(report.contains(revision), msg=report)
    client_program_abort_request_preparation(parent).unwrap()
    assert_true(
      client_program_project_request_check_outcome(
        parent,
        receipt,
        original,
        wire,
        context,
        "text",
        revision,
        text.length(),
        None,
        0,
        None,
        0,
        "corr:" + "c".repeat(32),
        None,
        supplied_namespace,
      ).unwrap()
      is None,
    )
  }
}

///|
test "Request Query projection refuses another equal-input original failure" {
  let environment = original_lookup_diagnostic_environment(false)
  let wire = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let publication = @source_publication.prepare_published_query_environment(
    environment, wire,
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let (foreign, other) = request_diagnostic_test_parent()
  let prepare = (parent, receipt) => {
    client_program_prepare_request_source_computation(
      parent,
      receipt,
      request_diagnostic_test_json("{\"format\":\"sql\",\"text\":\"SELECT (\"}"),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    )
  }
  let original = prepare(parent, receipt)
  let other_result = prepare(foreign, other)
  assert_true(original is Err(_) && other_result is Err(_))
  assert_true(
    client_program_project_request_check_outcome(
      parent,
      receipt,
      other_result,
      wire,
      "ctx:" + "a".repeat(64),
      "text",
      "rev:" + "b".repeat(64),
      8,
      None,
      0,
      None,
      0,
      "corr:" + "c".repeat(32),
      None,
      None,
    )
    is Err(ForeignOriginal),
  )
  client_program_abort_request_preparation(parent).unwrap()
  client_program_abort_request_preparation(foreign).unwrap()
}
