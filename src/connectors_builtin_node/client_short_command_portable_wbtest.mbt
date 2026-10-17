///|
test "short Command check uses the same portable Owner and retains its original-selection limitation" {
  let environment = short_command_source_environment()
  let publication = short_command_source_publication(environment)
  let document = short_command_source_text()
  let context = "ctx:" + "a".repeat(64)
  let revision = "rev:" + "b".repeat(64)
  let node = client_program_check_source(
    document,
    "sql",
    environment,
    publication,
    None,
    None,
    context,
    revision,
    None,
    None,
    "corr:short-command",
    "bound_input",
    None,
  )
  let portable = @local_preparation.client_program_check_source(
    document,
    "sql",
    environment,
    publication,
    None,
    None,
    context,
    revision,
    None,
    None,
    "corr:short-command",
    "bound_input",
    None,
  )
  assert_eq(node, portable)
  assert_true(node.contains("\"verdict\":\"undetermined\""), msg=node)
  assert_true(node.contains("\"code\":\"implementation_limit\""), msg=node)
  assert_true(!node.contains("\"verdict\":\"verified\""), msg=node)
}

///|
test "ordinary Source lowering retains its existing original Command publication without an occurrence" {
  let environment = short_command_source_environment()
  let lowered = client_program_lower_source(
    "SELECT 1 AS id",
    "sql",
    environment,
    short_command_source_publication(environment),
    None,
  ).unwrap()
  assert_true(lowered.command_targets is Some(_))
  assert_true(lowered.command_selection is None)
}
