///|
fn retained_original_binding_report(
  protected_source : Bool,
  supplied_body : String,
  traversal_nodes? : Int? = None,
  traversal_text_bytes? : Int? = None,
) -> (@checked.CheckOutcome, String) {
  let document = if protected_source {
    "{\"version\":\"actql/0.1\",\"id\":\"original.private\",\"params\":{\"missing\":{\"type\":\"number\"},\"wrong\":{\"type\":\"number\"}},\"stages\":[{\"id\":\"main\",\"inputs\":{\"rows\":{\"connector\":\"private\",\"resource\":\"unavailable\",\"view\":\"v\"}},\"steps\":[{\"select\":[\"private_field\"],\"as\":\"selected\"}],\"results\":{\"r\":{\"from\":\"selected\",\"fields\":[\"private_field\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"r\"}}}}"
  } else {
    "{\"version\":\"actql/0.1\",\"id\":\"original.binding\",\"params\":{\"missing\":{\"type\":\"number\"},\"wrong\":{\"type\":\"number\"}},\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"rows\"},{\"derive\":{\"n\":\"$missing + $wrong\"}}],\"results\":{\"r\":{\"from\":\"rows\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"r\"}}}}"
  }
  let limits = @host.client_standard_program_preparation_limits().checking
  let program = @syntax.parse(document, limits.input).unwrap()
  let source = @stage_parameters.prepare(program, {
    max_parameters: 1024,
    max_nodes: 8192,
    max_depth: 64,
    max_text_bytes: 65536,
  }).unwrap()
  let (_, supplied) = admit_local_program_input("json", Some(supplied_body)).unwrap()
  let environment = binding_check_environment()
  let checking_limits = {
    ..limits,
    compilation: {
      ..limits.compilation,
      traversal: {
        ..limits.compilation.traversal,
        nodes: traversal_nodes.unwrap_or(limits.compilation.traversal.nodes),
        text_bytes: traversal_text_bytes.unwrap_or(
          limits.compilation.traversal.text_bytes,
        ),
      },
    },
  }
  // This is the sole original check, including its actual budget or settings
  // refusal. Projection cannot construct the read-only nested error wrappers.
  let outcome = @checked.check_parsed(
    program,
    environment,
    supplied,
    checking_limits,
    source_preparation=Some(source),
  )
  let report = client_program_project_original_check_outcome(
    program,
    source,
    supplied,
    None,
    outcome,
    environment,
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
    supplied_body.length(),
    "corr:original-binding",
    None,
  )
  (outcome, report)
}

///|
test "retained original binder refusal keeps supplied facts beside missing declarations" {
  for
    (body, actual) in [
      ("{\"wrong\":\"private-supplied\"}", "string"),
      ("{\"wrong\":null}", "null"),
    ] {
    let (outcome, report) = retained_original_binding_report(false, body)
    guard outcome is @checked.Rejected(diagnostic) &&
      @checked.diagnostic_cause(diagnostic)
      is Source(SourceView(Binding(Binding(issue)))) &&
      issue is BindingInput(Supplied, _) else {
      fail("the original checker must supply the actual binder refusal")
    }
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(
      report.contains("\"code\":\"parameter_value_required\""),
      msg=report,
    )
    assert_true(report.contains("\"parameter\":\"missing\""), msg=report)
    assert_true(
      report.contains("\"code\":\"supplied_value_type_mismatch\""),
      msg=report,
    )
    assert_true(report.contains("\"parameter\":\"wrong\""), msg=report)
    assert_true(report.contains("\"expected_type\":\"number\""), msg=report)
    assert_true(
      report.contains("\"actual_type\":\"" + actual + "\""),
      msg=report,
    )
    assert_true(!report.contains("program_invalid"), msg=report)
    assert_true(!report.contains("private-supplied"), msg=report)
    // Native retained inputs do not supply authored parameter coordinates.
    assert_true(!report.contains("\"pointer\":\"/wrong\""), msg=report)
  }
}

///|
test "retained Source refusal cannot invent an unexecuted supplied type check" {
  let (outcome, report) = retained_original_binding_report(
    true, "{\"wrong\":\"private-supplied\"}",
  )
  guard outcome is @checked.Rejected(diagnostic) &&
    @checked.diagnostic_cause(diagnostic) is Source(Registration(Selection(_))) else {
    fail("the original checker must stop at the actual Source selection")
  }
  assert_true(
    report.contains("\"code\":\"parameter_value_required\""),
    msg=report,
  )
  assert_true(report.contains("\"parameter\":\"missing\""), msg=report)
  assert_true(report.contains("unresolved_protected"), msg=report)
  assert_true(!report.contains("supplied_value_type_mismatch"), msg=report)
  assert_true(!report.contains("private_field"), msg=report)
  assert_true(!report.contains("private-supplied"), msg=report)
}

///|
test "retained original budgets and invalid settings do not become supplied type findings" {
  for
    (nodes, text_bytes, code) in [
      (8192, 1, "analysis_budget_exhausted"),
      (-1, 65536, "check_context_invalid"),
    ] {
    let (outcome, report) = retained_original_binding_report(
      false,
      "{\"wrong\":\"private-supplied\"}",
      traversal_nodes=Some(nodes),
      traversal_text_bytes=Some(text_bytes),
    )
    guard outcome is @checked.Rejected(diagnostic) &&
      @checked.diagnostic_category(diagnostic)
      is (CompileLimit | InvalidConfiguration) else {
      fail(
        "the actual checker must retain its budget or settings failure: " +
        report,
      )
    }
    assert_true(report.contains("\"code\":\"" + code + "\""), msg=report)
    assert_true(!report.contains("supplied_value_type_mismatch"), msg=report)
    assert_true(!report.contains("program_invalid"), msg=report)
    assert_true(!report.contains("private-supplied"), msg=report)
  }
}
