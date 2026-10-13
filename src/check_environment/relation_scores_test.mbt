///|
test "SourceView scores retain original schema member and facts ownership" {
  let facts = @json.parse(
    #|{"relation_scores":{"id":{"domain":"Relevance","normalization":"Identity","range":[0,1]}},"relation_keys":{"candidate_keys":[["id"]]},"opaque_extension":true}
  )
  let modes = carrier_modes(record_body(), "relation", facts=Some(facts))
  let schemas = check_carrier_schemas(modes, carrier_limits()).unwrap()
  let environment = contract_registry_environment(catalog_registry(reference_contents(
    data_policy_references(value_contract_policies(source_view_shape_values(read_mode_shapes(modes)))),
  )))
  let member = member_at(environment, SourceViews, 0).unwrap()
  let view = source_view_carrier(schemas, member).unwrap()
  let scores = source_view_relation_scores(view).unwrap()
  assert_true(source_view_relation_keys(view) is Some(_))
  assert_true(physical_equal(source_relation_scores_schema(scores), source_view_carrier_schema(view)))
  assert_eq(@decode.object_length(source_relation_scores_source(scores)), Some(1))
  let original = reference_member(source_relation_scores_reference(scores))
  assert_true(physical_equal(member_environment(original), member_environment(member)))
  assert_eq(member_index(original), member_index(member))
  let foreign = check_carrier_schemas(
    carrier_modes(record_body(), "relation", facts=Some(facts)), carrier_limits(),
  ).unwrap()
  assert_true(source_view_carrier(foreign, member) is None)
}

///|
test "SourceView score map shares the closed ScoreContract reader" {
  for wire in [
    "{\"relation_scores\":null}",
    "{\"relation_scores\":{\"id\":{}}}",
    "{\"relation_scores\":{\"id\":{\"domain\":\"\",\"normalization\":\"Identity\",\"range\":[0,1]}}}",
    "{\"relation_scores\":{\"id\":{\"domain\":\"Relevance\",\"normalization\":\"Identity\",\"range\":[1,0]}}}",
    "{\"relation_scores\":{\"id\":{\"domain\":\"Relevance\",\"normalization\":\"Identity\",\"range\":[0,1],\"higher_is_better\":false}}}",
    "{\"relation_scores\":{\"id\":{\"domain\":\"Relevance\",\"normalization\":\"Identity\",\"range\":[0,1],\"extra\":true}}}",
  ] {
    assert_true(check_carrier_schemas(
      carrier_modes(record_body(), "relation", facts=Some(@json.parse(wire))), carrier_limits(),
    ) is Err({ kind: InvalidBody, .. }))
  }
}

///|
test "SourceView score names require required nonnull Number fields" {
  for name in ["missing", "other", "at", "v"] {
    let facts : Json = { "relation_scores": { name: {
      "domain": "Relevance", "normalization": "Identity", "range": [0, 1],
    } } }
    assert_true(check_carrier_schemas(
      carrier_modes(record_body(), "relation", facts=Some(facts)), carrier_limits(),
    ) is Err({ kind: InvalidBody, .. }))
  }
  for name in ["p", "q"] {
    let facts : Json = { "relation_scores": { name: {
      "domain": "Relevance", "normalization": "Identity", "range": [0, 1],
    } } }
    assert_true(check_carrier_schemas(
      carrier_modes(relation_presence_body(), "relation", facts=Some(facts)), carrier_limits(),
    ) is Err({ kind: InvalidBody, .. }))
  }
}

///|
test "SourceView score admission preserves empty facts and cumulative work" {
  let modes = carrier_modes(record_body(), "relation", facts=Some(@json.parse(
    #|{"relation_scores":{}}
  )))
  let (_, _, work, _) = carrier_schema_usage(check_carrier_schemas(modes, carrier_limits()).unwrap())
  assert_true(check_carrier_schemas(modes, { ..carrier_limits(), max_work: work, }) is Ok(_))
  assert_true(check_carrier_schemas(modes, { ..carrier_limits(), max_work: work - 1, }) is Err({ kind: WorkLimit, .. }))
  assert_true(check_carrier_schemas(carrier_modes(record_body(), "relation"), carrier_limits()) is Ok(_))
}
