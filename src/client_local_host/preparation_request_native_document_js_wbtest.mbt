///|
test "static native Request checks raw large JSON once and compiles only for explain" {
  let (environment, publication) = request_query_publication_fixture()
  let document = " ".repeat(70000) + native_driver_program
  let parameters = " ".repeat(70000) + "{\"n\":9}"
  let (owner, input) = native_driver_parent(document + parameters)
  prepare_request_native_document_check(
    owner,
    input,
    document,
    @frontend.Json,
    Some(parameters),
    None,
    environment,
    publication,
  ).unwrap()
  assert_true(owner.submitted_intent is None && owner.compiled_program is None)
  assert_true(
    owner.program_check.unwrap().check_outcome is Some(@checked.Checked(_)),
  )
  let program = owner.held_program.unwrap()
  let outcome = owner.program_check.unwrap().check_outcome.unwrap()
  let report = project_request_completed_check_outcome(
      owner,
      input,
      "{\"environmentCid\":\"" +
      @checked.checking_environment_cid(environment) +
      "\",\"aliases\":[]}",
      "ctx:" + "a".repeat(64),
      "program",
      "rev:" + "b".repeat(64),
      document.length(),
      None,
      0,
      Some("rev:" + "c".repeat(64)),
      parameters.length(),
      "corr:" + "d".repeat(32),
      None,
      original_parameters=Some(parameters),
    )
    .unwrap()
    .unwrap()
  assert_true(report.contains("\"verdict\":\"verified\""), msg=report)
  assert_true(
    physical_equal(owner.program_check.unwrap().check_outcome.unwrap(), outcome),
  )
  let plan = request_native_static_plan_view(
    owner,
    input,
    environment,
    publication,
    request_program_module_manifests(),
  ).unwrap()
  assert_true(plan.contains("actql-plan-view/0.1"), msg=plan)
  assert_true(physical_equal(owner.held_program.unwrap(), program))
  assert_true(
    owner.program_source_free is None && !owner.program_body_attempted,
  )
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "static native Request preserves Parameters-first malformed input and same typed refusal" {
  let (environment, publication) = request_query_publication_fixture()
  let (owner, input) = native_driver_parent("{ malformed input")
  let result = prepare_request_native_document_check(
    owner,
    input,
    "{ malformed input",
    @frontend.Json,
    Some("{ malformed Parameters"),
    None,
    environment,
    publication,
  )
  assert_true(
    result is Err(Preparation(Parameters(@local_preparation.SuppliedSyntax(_)))),
  )
  assert_true(owner.program_json is None && owner.program_check is None)
  assert_true(owner.query_syntax is None && owner.submitted_intent is None)
  abort_request_preparation_after_cleanup(owner).unwrap()
}

///|
test "static native Request keeps SQL Pipe originals configured primary and declarations" {
  let (environment, publication) = request_query_publication_fixture()
  for
    (document, format) in [
      ("SELECT @n AS id", @frontend.Sql),
      ("WITH seed AS (SELECT @n AS id) FROM seed |> SELECT id", @frontend.Text),
    ] {
    let (owner, input) = native_driver_parent(document)
    let checked = prepare_request_native_document_check(
      owner,
      input,
      document,
      format,
      Some("{\"n\":7}"),
      Some("{\"n\":{\"type\":\"number\"}}"),
      environment,
      publication,
    )
    match checked {
      Err(QuerySyntax(Frontend(@frontend.QuerySyntax(issue)))) =>
        fail(@debug.to_string(issue))
      Err(issue) => {
        let original : Error = issue
        fail(@debug.to_string(original))
      }
      Ok(_) => ()
    }
    checked.unwrap()
    let syntax = owner.query_syntax.unwrap().query.unwrap().unwrap()
    assert_true(owner.native_query_declarations is Some(_))
    let plan = request_native_static_plan_view(
      owner,
      input,
      environment,
      publication,
      request_program_module_manifests(),
    ).unwrap()
    assert_true(plan.contains("actql-plan-view/0.1"), msg=plan)
    assert_true(
      physical_equal(
        owner.query_syntax.unwrap().query.unwrap().unwrap(),
        syntax,
      ),
    )
    assert_true(owner.submitted_intent is None && !owner.program_body_attempted)
    abort_request_preparation_after_cleanup(owner).unwrap()
  }
}

///|
test "static native Request foreign input refuses before parser and capacity changes" {
  let (environment, publication) = request_query_publication_fixture()
  let (owner, input) = native_driver_parent("SELECT 2 AS id")
  let before = @resources.ledger_usage(owner.ledger)
  assert_true(
    prepare_request_native_document_check(
      owner,
      [1],
      "SELECT 2 AS id",
      @frontend.Sql,
      None,
      None,
      environment,
      publication,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  assert_true(owner.query_syntax is None && owner.program_json is None)
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(
    prepare_request_native_document_check(
      owner,
      input,
      "SELECT 2 AS id",
      @frontend.Sql,
      None,
      None,
      environment,
      publication,
    )
    is Err(Preparation(WrongPhase)),
  )
}

///|
test "static native Request retains explicit root NULL as an invalid supplied original" {
  let (environment, publication) = request_query_publication_fixture()
  let (owner, input) = native_driver_parent(native_driver_program)
  let result = prepare_request_native_document_check(
    owner,
    input,
    native_driver_program,
    @frontend.Json,
    Some("null"),
    None,
    environment,
    publication,
  )
  assert_true(
    owner.native_parameters is Some(original) && @decode.is_null(original),
  )
  assert_true(result is Err(CheckOutcome(@checked.Rejected(_))))
  assert_true(owner.compiled_program is None && owner.submitted_intent is None)
  abort_request_preparation_after_cleanup(owner).unwrap()
}

///|
test "static native Request preserves original private Source and authored Effect reports" {
  let (environment, publication) = request_query_publication_fixture()
  let protected_document = "{\"version\":\"actql/0.1\",\"id\":\"static-private-source\",\"stages\":[{\"id\":\"s\",\"inputs\":{\"rows\":{\"connector\":\"private\",\"resource\":\"missing\",\"view\":\"v\"}},\"steps\":[{\"from\":\"rows\",\"select\":[\"id\"],\"as\":\"r\"}],\"results\":{\"out\":{\"from\":\"r\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"s\",\"result\":\"out\"}}}}"
  let effect = native_driver_program.replace(
    old="\"results\":{\"rows\":",
    new="\"effects\":{\"save\":{\"create\":{\"target\":\"connector://private/missing\",\"mapping\":\"mapping:missing.v1\",\"from\":{\"result\":\"rows\"}}}},\"results\":{\"rows\":",
  )
  let wire = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let context = "ctx:" + "a".repeat(64)
  let revision = "rev:" + "b".repeat(64)
  let correlation = "corr:" + "c".repeat(32)
  for document in [protected_document, effect] {
    let expected = @local_preparation.client_program_check_program(
      document,
      environment,
      wire,
      None,
      context,
      revision,
      None,
      correlation,
      "bound_input",
      None,
    )
    let (owner, input) = native_driver_parent(document)
    let checked = prepare_request_native_document_check(
      owner,
      input,
      document,
      @frontend.Json,
      None,
      None,
      environment,
      publication,
    )
    let actual = match checked {
      Ok(_) =>
        project_request_completed_check_outcome(
          owner,
          input,
          wire,
          context,
          "program",
          revision,
          @utf8.encode(document).length(),
          Some(revision),
          0,
          None,
          0,
          correlation,
          None,
          original_document=Some(document),
        )
        .unwrap()
        .unwrap()
      Err(issue) =>
        project_request_check_outcome(
          owner,
          input,
          issue,
          wire,
          context,
          "program",
          revision,
          @utf8.encode(document).length(),
          Some(revision),
          0,
          None,
          0,
          correlation,
          None,
          original_document=Some(document),
        )
        .unwrap()
        .unwrap()
    }
    assert_eq(actual, expected)
    assert_true(
      owner.compiled_program is None && owner.submitted_intent is None,
    )
    abort_request_preparation_after_cleanup(owner).unwrap()
  }
}
