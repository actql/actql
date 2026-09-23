///|
fn effect_mapping_literal_rules(
  effects : String,
  mappings : @environment.MappingContractShapes,
) -> EffectMappingRules {
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, 10).unwrap()
  let shapes = bind_effect_mapping_shapes(bindings, mappings, 2).unwrap()
  bind_effect_mapping_rules(shapes, 50).unwrap()
}

///|
fn effect_mapping_literal_limits(
  work? : Int = 20,
  nodes? : Int = 10,
  text? : Int = 100,
) -> EffectMappingLiteralLimits {
  {
    max_work: work,
    max_value_nodes: nodes,
    max_value_depth: 10,
    max_value_text_bytes: text,
  }
}

///|
test "inline create literals retain exact typed values and aggregate usage" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"payload\":{\"Name\":7}}}}"
  let rules = effect_mapping_literal_rules(
    effects,
    effect_mapping_shape_fixture(),
  )
  let values = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(work=4, nodes=2, text=0),
  ).unwrap()
  assert_true(physical_equal(effect_mapping_literals_rules(values), rules))
  assert_eq(effect_mapping_literal_count(values), 2)
  assert_eq(effect_mapping_literals_usage(values), (4, 2, 0))
  let first = effect_mapping_literal_at(values, 0).unwrap()
  assert_true(
    physical_equal(
      effect_mapping_literal_rule(first),
      effect_mapping_rule_at(rules, 0).unwrap(),
    ),
  )
  assert_eq(effect_mapping_literal_target(first), "Name")
  assert_eq(effect_mapping_literal_origin(first), InlineCreate)
  assert_true(effect_mapping_literal_value(first) is Written(_))
  assert_true(effect_mapping_literal_at(values, 2) is None)
  assert_eq(
    effect_mapping_literal_issue_kind(
      admit_effect_mapping_literals(
        rules,
        effect_mapping_literal_limits(work=3, nodes=2, text=0),
      ).unwrap_err(),
    ),
    WorkLimit,
  )
  assert_eq(
    effect_mapping_literal_issue_kind(
      admit_effect_mapping_literals(
        rules,
        effect_mapping_literal_limits(work=4, nodes=1, text=0),
      ).unwrap_err(),
    ),
    WorkLimit,
  )
}

///|
test "inline payload and set literals reject values outside target type" {
  let create = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"payload\":{\"Name\":\"text\"}}}}"
  let mappings = effect_mapping_shape_fixture()
  let rules = effect_mapping_literal_rules(create, mappings)
  let issue = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(),
  ).unwrap_err()
  assert_eq(
    effect_mapping_literal_issue_kind(issue),
    IncompatibleLiteral("Name"),
  )
  assert_eq(effect_mapping_literal_issue_stage(issue), 0)
  assert_eq(effect_mapping_literal_issue_effect(issue), "create")
  let update = "{\"update\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":{\"literal\":\"text\"}}}}}"
  let rule = "[{\"effect_kind\":\"update\",\"permissions\":[\"scope:update\"],\"selector_class\":\"id\",\"write_fields\":[\"Name\"]}]"
  let mappings = effect_mapping_shape_fixture_with_body(rule, "[]", "amount")
  let rules = effect_mapping_literal_rules(update, mappings)
  let issue = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(),
  ).unwrap_err()
  assert_eq(
    effect_mapping_literal_issue_kind(issue),
    IncompatibleLiteral("Name"),
  )
}

///|
test "literal text admission charges UTF-8 bytes across all Stage members" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"payload\":{\"Name\":\"é\"}}}}"
  let rule = "[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}]"
  let mappings = effect_mapping_shape_fixture_with_body(
    rule,
    "[]",
    "amount",
    target_type="string",
  )
  let rules = effect_mapping_literal_rules(effects, mappings)
  let admitted = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(work=4, nodes=2, text=4),
  ).unwrap()
  assert_eq(effect_mapping_literals_usage(admitted), (4, 2, 4))
  assert_eq(
    effect_mapping_literal_issue_kind(
      admit_effect_mapping_literals(
        rules,
        effect_mapping_literal_limits(work=4, nodes=2, text=3),
      ).unwrap_err(),
    ),
    WorkLimit,
  )
}

///|
test "Mapping-owned literals enforce null behavior and required omission" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"}}}}"
  let rule = "[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}]"
  let numeric = effect_mapping_shape_fixture_with_body(
    rule,
    "[]",
    "amount",
    row_mapping="{\"Name\":{\"literal\":7,\"null_behavior\":\"reject\"}}",
  )
  let rules = effect_mapping_literal_rules(effects, numeric)
  let admitted = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(work=6, nodes=2, text=0),
  ).unwrap()
  assert_eq(effect_mapping_literal_count(admitted), 2)
  assert_eq(
    effect_mapping_literal_origin(
      effect_mapping_literal_at(admitted, 0).unwrap(),
    ),
    ContractRow,
  )
  let rejected = effect_mapping_shape_fixture_with_body(
    rule,
    "[]",
    "amount",
    row_mapping="{\"Name\":{\"literal\":null,\"null_behavior\":\"reject\"}}",
  )
  let rules = effect_mapping_literal_rules(effects, rejected)
  assert_eq(
    effect_mapping_literal_issue_kind(
      admit_effect_mapping_literals(rules, effect_mapping_literal_limits()).unwrap_err(),
    ),
    RejectedNull("Name"),
  )
  let omitted = effect_mapping_shape_fixture_with_body(
    rule,
    "[]",
    "amount",
    row_mapping="{\"Name\":{\"literal\":null,\"null_behavior\":\"omit\"}}",
  )
  let rules = effect_mapping_literal_rules(effects, omitted)
  let admitted = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(work=6, nodes=0, text=0),
  ).unwrap()
  assert_eq(effect_mapping_literals_usage(admitted), (6, 0, 0))
  assert_true(
    effect_mapping_literal_value(
      effect_mapping_literal_at(admitted, 0).unwrap(),
    )
    is Omitted,
  )
  let required = effect_mapping_shape_fixture_with_body(
    rule,
    "[\"Name\"]",
    "amount",
    row_mapping="{\"Name\":{\"literal\":null,\"null_behavior\":\"omit\"}}",
  )
  let rules = effect_mapping_literal_rules(effects, required)
  assert_eq(
    effect_mapping_literal_issue_kind(
      admit_effect_mapping_literals(rules, effect_mapping_literal_limits()).unwrap_err(),
    ),
    RequiredOmission("Name"),
  )
  let null_write = effect_mapping_shape_fixture_with_body(
    rule,
    "[]",
    "amount",
    row_mapping="{\"Name\":{\"literal\":null,\"null_behavior\":\"write_null\"}}",
  )
  let rules = effect_mapping_literal_rules(effects, null_write)
  let admitted = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(work=6, nodes=2, text=0),
  ).unwrap()
  assert_true(
    effect_mapping_literal_value(
      effect_mapping_literal_at(admitted, 0).unwrap(),
    )
    is Written(_),
  )
  let nonnullable = effect_mapping_shape_fixture_with_body(
    rule,
    "[]",
    "amount",
    target_nullable=false,
    row_mapping="{\"Name\":{\"literal\":null,\"null_behavior\":\"write_null\"}}",
  )
  let rules = effect_mapping_literal_rules(effects, nonnullable)
  assert_eq(
    effect_mapping_literal_issue_kind(
      admit_effect_mapping_literals(rules, effect_mapping_literal_limits()).unwrap_err(),
    ),
    IncompatibleLiteral("Name"),
  )
}
