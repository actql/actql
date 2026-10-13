///|
test "SourceView key facts retain exact owner schema and conditional tuple declarations" {
  let facts = @json.parse(
    (
      #|{"relation_keys":{"candidate_keys":[["id"],["id","at"]]},"uninterpreted_extension":{"name":"still opaque"}}
    ),
  )
  let modes = carrier_modes(record_body(), "relation", facts=Some(facts))
  let schemas = check_carrier_schemas(modes, carrier_limits()).unwrap()
  let references = data_policy_references(
    value_contract_policies(source_view_shape_values(read_mode_shapes(modes))),
  )
  let environment = contract_registry_environment(
    catalog_registry(reference_contents(references)),
  )
  let view = member_at(environment, SourceViews, 0).unwrap()
  let carrier = source_view_carrier(schemas, view).unwrap()
  let keys = source_view_relation_keys(carrier).unwrap()
  assert_eq(source_relation_key_count(keys), 2)
  assert_eq(
    @decode.array_length(source_relation_key_at(keys, 0).unwrap()),
    Some(1),
  )
  assert_eq(
    @decode.text(
      @decode.element_at(source_relation_key_at(keys, 1).unwrap(), 1).unwrap(),
    ),
    Ok("at"),
  )
  assert_true(
    physical_equal(
      source_relation_key_schema(keys),
      source_view_carrier_schema(carrier),
    ),
  )
  let declared_member = reference_member(source_relation_key_reference(keys))
  // Member access creates a handle for its original environment and index;
  // wrapper object identity is not the Member's ownership contract.
  assert_true(
    physical_equal(
      member_environment(declared_member),
      member_environment(view),
    ),
  )
  assert_eq(member_section(declared_member), SourceViews)
  assert_eq(member_index(declared_member), member_index(view))
  assert_true(
    physical_equal(
      source_view_carrier(schemas, declared_member).unwrap(),
      carrier,
    ),
  )
  let foreign_modes = carrier_modes(
    record_body(),
    "relation",
    facts=Some(facts),
  )
  let foreign = check_carrier_schemas(foreign_modes, carrier_limits()).unwrap()
  assert_true(source_view_carrier(foreign, view) is None)
  assert_true(source_relation_key_at(keys, -1) is None)
  assert_true(source_relation_key_at(keys, 2) is None)
}

///|
test "SourceView relation key component is closed without closing outer facts" {
  for
    wire in [
      "{\"relation_keys\":null}", "{\"relation_keys\":{}}", "{\"relation_keys\":{\"candidate_keys\":null}}",
      "{\"relation_keys\":{\"candidate_keys\":[]}}", "{\"relation_keys\":{\"candidate_keys\":[[]]}}",
      "{\"relation_keys\":{\"candidate_keys\":[[\"id\",\"id\"]]}}", "{\"relation_keys\":{\"candidate_keys\":[[\"id\"],[\"id\"]]}}",
      "{\"relation_keys\":{\"candidate_keys\":[[1]]}}", "{\"relation_keys\":{\"candidate_keys\":[[\"\"]]}}",
      "{\"relation_keys\":{\"candidate_keys\":[[\"id\"]],\"extra\":true}}",
    ] {
    let modes = carrier_modes(
      record_body(),
      "relation",
      facts=Some(@json.parse(wire)),
    )
    guard check_carrier_schemas(modes, carrier_limits()) is Err(issue) else {
      fail("invalid closed key declaration")
    }
    assert_eq(issue.kind, InvalidBody)
  }
  assert_true(
    check_carrier_schemas(
      carrier_modes(
        record_body(),
        "relation",
        facts=Some(@json.parse("{\"uninterpreted_extension\":true}")),
      ),
      carrier_limits(),
    )
    is Ok(_),
  )
}

///|
test "SourceView keys require original required nonnull comparable fields" {
  for name in ["missing", "v"] {
    let facts = ({ "relation_keys": { "candidate_keys": [[name]] } } : Json)
    let modes = carrier_modes(record_body(), "relation", facts=Some(facts))
    guard check_carrier_schemas(modes, carrier_limits()) is Err(issue) else {
      fail("invalid key domain")
    }
    assert_eq(issue.kind, InvalidBody)
  }
  for name in ["p", "q"] {
    let facts = ({ "relation_keys": { "candidate_keys": [[name]] } } : Json)
    let modes = carrier_modes(
      relation_presence_body(),
      "relation",
      facts=Some(facts),
    )
    guard check_carrier_schemas(modes, carrier_limits()) is Err(issue) else {
      fail("conditional or nullable key")
    }
    assert_eq(issue.kind, InvalidBody)
  }
}

///|
test "SourceView key admission shares the original cumulative work budget" {
  let facts = @json.parse(
    "{\"relation_keys\":{\"candidate_keys\":[[\"id\"],[\"id\",\"at\"]]}}",
  )
  let modes = carrier_modes(record_body(), "relation", facts=Some(facts))
  let (_, _, work, _) = carrier_schema_usage(
    check_carrier_schemas(modes, carrier_limits()).unwrap(),
  )
  assert_true(
    check_carrier_schemas(modes, { ..carrier_limits(), max_work: work, })
    is Ok(_),
  )
  guard check_carrier_schemas(modes, { ..carrier_limits(), max_work: work - 1, })
    is Err(issue) else {
    fail("one fewer unit of work cannot admit the same declarations")
  }
  assert_eq(issue.kind, WorkLimit)
}
