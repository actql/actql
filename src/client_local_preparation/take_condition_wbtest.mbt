///|
test "public Take condition keeps default admission separate from actual binding" {
  let environment = binding_check_environment()
  let publication = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let check = fn(scope, parameters) {
    client_program_check_source(
      "SELECT 1 AS n ORDER BY n LIMIT @count",
      "sql",
      environment,
      publication,
      Some("{\"count\":{\"type\":\"number\",\"default\":0}}"),
      parameters,
      "ctx:take-condition",
      "rev:" + "a".repeat(64),
      Some("rev:" + "b".repeat(64)),
      parameters.map(_ => "rev:" + "c".repeat(64)),
      "corr:take-condition",
      scope,
      None,
    )
  }
  let template = check("template_only", None)
  assert_true(template.contains("\"verdict\":\"verified\""), msg=template)
  assert_true(
    template.contains("\"code\":\"parameter_consumer_condition\""),
    msg=template,
  )
  assert_true(!template.contains("parameter_value_required"), msg=template)
  assert_true(template.contains("\"verdict\":\"no\""), msg=template)
  let omitted = check("bound_input", None)
  assert_true(omitted.contains("\"verdict\":\"invalid\""), msg=omitted)
  assert_true(omitted.contains("operation_parameter_invalid"), msg=omitted)
  let replacement = check("bound_input", Some("{\"count\":1}"))
  assert_true(replacement.contains("\"verdict\":\"verified\""), msg=replacement)
  assert_true(replacement.contains("\"requirements\":[]"), msg=replacement)
  assert_true(replacement.contains("\"verdict\":\"yes\""), msg=replacement)
}

///|
test "Take condition reporting refuses omission and foreign complete-template membership" {
  let environment = binding_check_environment()
  let publication = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let prepare = fn() {
    let findings : Array[CheckFinding] = []
    let stop = check_source_findings(
      findings,
      "SELECT 1 AS n ORDER BY n LIMIT @count",
      "sql",
      environment,
      publication,
      Some("{\"count\":{\"type\":\"number\",\"default\":0}}"),
      None,
      TemplateOnly,
      None,
    )
    (findings, stop)
  }
  let (findings, stop) = prepare()
  guard stop is TemplateVerified(_) else { fail("original complete template") }
  let documents : CheckDocuments = {
    scope: TemplateOnly,
    structured_program: false,
    program_pointer: None,
    source_revision: "rev:" + "a".repeat(64),
    source_bytes: 50,
    declarations_revision: Some("rev:" + "b".repeat(64)),
    declarations_bytes: 50,
    parameters_revision: None,
    parameters_bytes: 0,
  }
  let report = check_outcome_attempt(
    findings, stop, "ctx:condition", "corr:condition", documents, 0,
  ).unwrap()
  assert_true(report.contains("reporting_budget_exhausted"), msg=report)
  assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
  assert_true(!report.contains("\"verdict\":\"verified\""), msg=report)
  let (foreign, _) = prepare()
  assert_true(
    check_outcome_attempt(
      foreign, stop, "ctx:condition", "corr:condition", documents, 128,
    )
    is None,
  )
}
