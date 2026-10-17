///|
test "Node check ABI forwards the same original Host outcome and opaque original_namespace" {
  let environment = store_public_bridge_fixture("collection")
  let publication = "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let context = "ctx:" + "a".repeat(64)
  let revision = "rev:" + "b".repeat(64)
  let original_namespace = client_program_check_source_namespace(
    environment,
    publication,
    "visible",
    "sha256:" + "c".repeat(64),
    context,
    revision,
  ).unwrap()
  // The alias is the portable Owner's original opaque value, not an equal-CID
  // reconstruction or a Node-specific public constructor.
  let original : @local_preparation.ClientCheckSourceNamespace = original_namespace
  for
    document in [
      "SELECT 1 AS value", "SELECT 1 / 'text' AS value", "SELECT * FROM missing",
      "SELECT (",
    ] {
    for selected in [None, Some(original)] {
      let report = client_program_check_source(
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
        "corr:portable",
        "bound_input",
        selected,
      )
      assert_eq(
        report,
        @local_preparation.client_program_check_source(
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
          "corr:portable",
          "bound_input",
          selected,
        ),
      )
    }
  }
  assert_eq(
    client_program_check_context_identity(environment),
    @local_preparation.client_program_check_context_identity(environment),
  )
  assert_eq(
    client_program_check_compiler_identity(),
    @local_preparation.client_program_check_compiler_identity(),
  )
  assert_eq(
    client_program_check_unavailable("corr:portable"),
    @local_preparation.client_program_check_unavailable("corr:portable"),
  )
}

///|
test "Node structured check forwards the original selector range and refuses foreign context" {
  let environment = store_public_bridge_fixture("collection")
  let publication = "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let range = client_program_check_source_selector_range(environment, []).unwrap()
  let original : @local_preparation.ClientCheckSourceSelectorRange = range
  let context = "ctx:" + "a".repeat(64)
  let revision = "rev:" + "b".repeat(64)
  let original_namespace = client_program_check_source_selector_namespace(
    original,
    "visible",
    "sha256:" + "c".repeat(64),
    context,
    revision,
  ).unwrap()
  let selected : @local_preparation.ClientCheckSourceSelectorNamespace = original_namespace
  for
    body in [
      "{}", "{\"version\":\"actql/0.1\",\"id\":\"invalid\",\"stages\":[]}",
    ] {
    assert_eq(
      client_program_check_program(
        body,
        environment,
        publication,
        None,
        context,
        revision,
        None,
        "corr:portable",
        "bound_input",
        Some(selected),
      ),
      @local_preparation.client_program_check_program(
        body,
        environment,
        publication,
        None,
        context,
        revision,
        None,
        "corr:portable",
        "bound_input",
        Some(selected),
      ),
    )
  }
  let foreign = client_program_check_program(
    "{}",
    environment,
    publication,
    None,
    "ctx:" + "d".repeat(64),
    revision,
    None,
    "corr:portable",
    "bound_input",
    Some(selected),
  )
  assert_true(
    foreign.contains("\"code\":\"check_context_invalid\""),
    msg=foreign,
  )
}
