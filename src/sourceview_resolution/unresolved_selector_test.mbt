///|
// Empty environment CID independently calculated with sorted compact JSON and
// SHA-256; no resolver output supplies an expected value.
fn selector_empty_catalog() -> @environment.SourceRequestContracts {
  fixture_catalog(
    "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"evidence_bundle_cid\":\"sha256:bf3e299a7386f7442aa04abc23901a1b3f580b490e6c625fe4ea686dce61032c\",\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}",
    "sha256:bf3e299a7386f7442aa04abc23901a1b3f580b490e6c625fe4ea686dce61032c",
  )
}

///|
test "unresolved selector retains its owners and normalized Program cursor" {
  let catalog = selector_empty_catalog()
  let input = "{\"connector\":\"crm/main\",\"resource\":\"missing/~🧭\",\"view\":\"e\\u0301/~🧭\",\"request\":{\"value\":null}}"
  let inputs = fixture_inputs(
    input,
    stage_bodies=Some(
      "{\"id\":\"a\",\"inputs\":{\"e\\u0301/~🧭\":" +
      input +
      "},\"steps\":[],\"results\":{\"r\":{}}}",
    ),
  )
  guard resolve(inputs, catalog, caps()) is Err(issue) else {
    fail("expected unresolved selector")
  }
  assert_eq(issue.kind, Unresolved)
  let declaration = unresolved_selector_declaration(issue, inputs, catalog).unwrap()
  assert_true(physical_equal(declaration, @inputs.at(inputs, 0).unwrap()))
  assert_eq(declaration.connector, "crm/main")
  assert_eq(declaration.resource, "missing/~🧭")
  assert_eq(declaration.view, Some("é/~🧭"))
  assert_eq(@decode.cursor_path(declaration.source), [
    @source.Key("stages"),
    @source.Index(0),
    @source.Key("inputs"),
    @source.Key("é/~🧭"),
  ])
  assert_eq(@decode.cursor_path(issue.source.unwrap()), [
    @source.Key("stages"),
    @source.Index(0),
    @source.Key("inputs"),
    @source.Key("é/~🧭"),
    @source.Key("view"),
  ])
  let object = @decode.open_object(declaration.source).unwrap()
  assert_eq(
    @decode.text(@decode.required(object, "view").unwrap()).unwrap(),
    "e\u0301/~🧭",
  )
  let request = @decode.open_object(declaration.request.unwrap()).unwrap()
  assert_true(
    @decode.view(@decode.lookup(request, "value").unwrap()) is NullValue,
  )
}

///|
test "unresolved selector cannot be transplanted to another input or Catalog" {
  let catalog = selector_empty_catalog()
  let inputs = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"missing\",\"view\":\"v\"}",
  )
  guard resolve(inputs, catalog, caps()) is Err(issue) else {
    fail("expected unresolved selector")
  }
  let same = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"missing\",\"view\":\"v\"}",
  )
  let changed = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"other\",\"view\":\"v\"}",
  )
  assert_true(
    unresolved_selector_declaration(issue, inputs, catalog) is Some(_),
  )
  assert_true(
    unresolved_selector_declaration(issue, same, catalog) is None,
    msg="selector-input-custody",
  )
  assert_true(
    unresolved_selector_declaration(issue, changed, catalog) is None,
    msg="selector-changed-input-custody",
  )
  assert_true(
    unresolved_selector_declaration(issue, inputs, selector_empty_catalog())
    is None,
    msg="selector-catalog-custody",
  )
}

///|
test "omitted selector view retains its real enclosing input" {
  let catalog = selector_empty_catalog()
  let inputs = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"missing\"}",
  )
  guard resolve(inputs, catalog, caps()) is Err(issue) else {
    fail("expected unresolved selector")
  }
  let declaration = unresolved_selector_declaration(issue, inputs, catalog).unwrap()
  assert_eq(declaration.view, None)
  assert_true(physical_equal(issue.source.unwrap(), declaration.source))
  assert_eq(@decode.cursor_path(issue.source.unwrap()), [
    @source.Key("stages"),
    @source.Index(0),
    @source.Key("inputs"),
    @source.Key("remote"),
  ])
  assert_true(
    @decode.lookup(@decode.open_object(declaration.source).unwrap(), "view")
    is None,
  )
}

///|
test "budget and admission limits do not issue unresolved selector custody" {
  let catalog = selector_empty_catalog()
  let inputs = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"missing\"}",
  )
  for
    limits in [
      { ..caps(), max_work: 0, },
      { ..caps(), max_work: -1, },
      { ..caps(), max_inputs: 0, },
    ] {
    guard resolve(inputs, catalog, limits) is Err(issue) else {
      fail("expected limited selection")
    }
    assert_false(issue.kind == Unresolved)
    assert_true(unresolved_selector_declaration(issue, inputs, catalog) is None)
  }
}
