///|
test "portable Source publication parts preserve public and legacy primary recipes" {
  let legacy = original_dispatch_source("SELECT 1 AS n")
  let current = prepare_client_source_computation(
    legacy.intent,
    legacy.environment,
    legacy.publication,
    public_primary=true,
  ).unwrap()
  guard legacy.preparation is Pure(old) else { fail("Expected Pure legacy") }
  guard current.preparation is Pure(prepared) else {
    fail("Expected Pure public")
  }
  assert_eq(prepared_client_result_name(old, 0), Some("answer"))
  assert_eq(prepared_client_result_name(prepared, 0), Some("main"))
  assert_eq(
    client_source_computation_originals(current),
    client_source_computation_originals(legacy),
  )
  assert_eq(
    client_source_computation_source(current),
    ("SELECT 1 AS n", "sql", None),
  )
  assert_true(
    client_source_computation_matches(
      current,
      legacy.intent,
      legacy.environment,
    ),
  )
  let copied_intent = prepare_client_submitted_intent(
    client_submitted_intent_wire(legacy.intent),
    65536,
    8192,
    64,
  ).unwrap()
  assert_false(
    client_source_computation_matches(
      current,
      copied_intent,
      legacy.environment,
    ),
  )
}

///|
test "portable Source publication parts retain unused and foreign metadata refusals" {
  let original = original_dispatch_source("SELECT 1 AS n")
  let malformed = original.publication[:original.publication.length() - 1].to_owned() +
    ",\"storeTargets\":null}"
  assert_true(
    prepare_client_source_computation(
      original.intent,
      original.environment,
      malformed,
    )
    is Err(Publication(_)),
  )
  let foreign = original.publication.replace(
    old=@checked.checking_environment_cid(original.environment),
    new="sha256:" + "0".repeat(64),
  )
  assert_true(
    prepare_client_source_computation(
      original.intent,
      original.environment,
      foreign,
    )
    is Err(Publication(_)),
  )
}

///|
test "portable Source Catalog reuse preserves the ordinary checked Program identities" {
  let original = original_dispatch_source(
    "SELECT id FROM records WHERE id > 0 ORDER BY id",
  )
  guard original.preparation is Pure(actual) else { fail("Expected Pure") }
  let (
    context,
    table_writes,
    update_targets,
    store_targets,
    command_targets,
    catalog,
  ) = @source_publication.bind_published_query_parts_with_catalog(
    original.environment,
    original.publication,
    None,
  ).unwrap()
  assert_true(
    physical_equal(@checked.source_catalog_owner(catalog), original.environment),
  )
  let lowered = @source_frontend.lower(
    original.source_document,
    @source_frontend.Sql,
    Some(context),
    table_writes~,
    update_targets~,
    store_targets~,
    command_targets~,
  ).unwrap()
  guard lowered.program is Some(parsed) else { fail("Expected Program") }
  // The legacy parsed entry still admits its Environment normally. Its
  // checked identities must agree with the caller using the original Catalog.
  let ordinary = prepare_parsed_effect_free_client_program(
    parsed,
    original.environment,
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
  let actual_checked = @strategy.graph_program(prepared_client_graph(actual))
  let ordinary_checked = @strategy.graph_program(
    prepared_client_graph(ordinary),
  )
  assert_eq(
    @checked.unit_count(actual_checked),
    @checked.unit_count(ordinary_checked),
  )
  for unit in 0..<@checked.unit_count(actual_checked) {
    assert_eq(
      @checked.unit_definition_cid(actual_checked, unit),
      @checked.unit_definition_cid(ordinary_checked, unit),
    )
    assert_eq(
      @checked.unit_used_values_cid(actual_checked, unit),
      @checked.unit_used_values_cid(ordinary_checked, unit),
    )
  }
}
