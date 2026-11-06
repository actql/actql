///|
test "portable check emits the complete original runnable contract without a Run" {
  let report = binding_check_report("SELECT 1 AS value", "sql")
  assert_true(report.contains("\"outcome\":\"completed\""), msg=report)
  assert_true(report.contains("\"verdict\":\"verified\""), msg=report)
  assert_true(
    report.contains("\"runnable\":{\"reasons\":[],\"verdict\":\"yes\"}"),
    msg=report,
  )
  let invalid = binding_check_report("SELECT 1 / 'text' AS value", "sql")
  assert_true(invalid.contains("\"verdict\":\"invalid\""), msg=invalid)
  assert_true(invalid.contains("\"verdict\":\"no\""), msg=invalid)
  assert_true(!invalid.contains("\"prepared\""), msg=invalid)
}

///|
test "portable original original_namespace refuses foreign context source and environment" {
  let original = binding_check_environment()
  let publication = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(original) +
    "\",\"aliases\":[]}"
  let context = "ctx:" + "a".repeat(64)
  let revision = "rev:" + "b".repeat(64)
  let original_namespace = client_program_check_source_namespace(
    original,
    publication,
    "visible",
    "sha256:" + "c".repeat(64),
    context,
    revision,
  ).unwrap()
  let check = fn(environment, context_ref, source_revision) {
    client_program_check_source(
      "SELECT * FROM missing",
      "sql",
      environment,
      publication,
      None,
      None,
      context_ref,
      source_revision,
      None,
      None,
      "corr:portable",
      "bound_input",
      Some(original_namespace),
    )
  }
  let absent = check(original, context, revision)
  assert_true(absent.contains("\"verdict\":\"invalid\""), msg=absent)
  assert_true(absent.contains("query_alias_absent"), msg=absent)
  for
    report in [
      check(original, "ctx:" + "d".repeat(64), revision),
      check(original, context, "rev:" + "e".repeat(64)),
      check(environment(), context, revision),
    ] {
    assert_true(
      report.contains("\"code\":\"check_context_invalid\""),
      msg=report,
    )
    assert_true(!report.contains("query_alias_absent"), msg=report)
  }
}

///|
test "portable input admission preserves explicit formats malformed parameters and missing values" {
  assert_true(admit_local_program_input("other", None) is Err(InvalidFormat))
  assert_true(
    admit_local_program_input("json", Some("{")) is Err(SuppliedSyntax(_)),
  )
  assert_true(admit_local_program_input("json", None) is Ok((Json, None)))
  assert_true(
    admit_local_program_input("yaml", Some("{\"n\":null}"))
    is Ok((Yaml, Some(_))),
  )
}

///|
test "original textual Parameters reader retains normalization and typed failures" {
  let (source_limits, tree_limits) = local_parameter_input_limits()
  let supplied = admit_local_parameter_document(
    "{\"é\":7}", source_limits, tree_limits,
  ).unwrap()
  let object = @decode.open_object(supplied).unwrap()
  let value = @decode.lookup(object, "é").unwrap()
  assert_eq(@decode.safe_integer(value).unwrap(), 7L)
  assert_true(
    admit_local_parameter_document(
      "{\"é\":1,\"é\":2}", source_limits, tree_limits,
    )
    is Err(SuppliedSyntax({ issue: DuplicateKey("é"), .. })),
  )
  assert_true(
    admit_local_parameter_document("{", source_limits, tree_limits)
    is Err(SuppliedSyntax(_)),
  )
  assert_true(
    admit_local_parameter_document("{\"n\":1}", source_limits, {
      ..tree_limits,
      max_nodes: 1,
    })
    is Err(SuppliedAdmission({ kind: BudgetExceeded, .. })),
  )
}

///|
test "original textual Parameters reader uses the already selected syntax limits" {
  let (source_limits, tree_limits) = local_parameter_input_limits()
  // A caller may back the actual raw wire independently of the retained value.
  // Whitespace does not fabricate more nodes or a larger scalar allowance.
  let document = " ".repeat(70000) + "null"
  assert_true(
    admit_local_program_input("json", Some(document)) is Err(SuppliedSyntax(_)),
  )
  let original = admit_local_parameter_document(
    document,
    { ..source_limits, max_input_bytes: document.length(), },
    tree_limits,
  ).unwrap()
  assert_true(@decode.is_null(original))
  assert_eq(@decode.admission_usage(original).nodes, 1)
  assert_eq(source_limits.max_input_bytes, 65536)
  assert_eq(tree_limits.max_string_bytes, 65536)
}
