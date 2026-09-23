///|
fn effect_mapping_rule_inputs(
  effects : String,
  max_bind_work : Int,
) -> EffectMappingShapes {
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, max_bind_work).unwrap()
  bind_effect_mapping_shapes(
    bindings,
    effect_mapping_shape_fixture(),
    effect_result_binding_count(bindings),
  ).unwrap()
}

///|
test "checked create derives exact Mapping permission from retained source" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"}}}}"
  let shapes = effect_mapping_rule_inputs(effects, 4)
  let rules = bind_effect_mapping_rules(shapes, 21).unwrap()
  assert_true(physical_equal(effect_mapping_rules_shapes(rules), shapes))
  assert_eq(effect_mapping_rule_count(rules), 2)
  assert_eq(effect_mapping_rules_work(rules), 21)
  let first = effect_mapping_rule_at(rules, 0).unwrap()
  assert_true(
    physical_equal(
      effect_mapping_rule_effect(first),
      effect_mapping_shape_at(shapes, 0).unwrap(),
    ),
  )
  let selection = effect_mapping_rule_selection(first)
  let conversions = effect_mapping_rule_conversions(first)
  assert_eq(@environment.mapping_conversion_count(conversions), 0)
  assert_eq(
    @environment.mapping_permission_rule(selection),
    ("create", "none", ["Name"]),
  )
  assert_eq(@environment.mapping_permission_names(selection), ["scope:create"])
  assert_true(effect_mapping_rule_at(rules, 2) is None)
  assert_eq(
    effect_mapping_rule_issue_kind(
      bind_effect_mapping_rules(shapes, 20).unwrap_err(),
    ),
    WorkLimit,
  )
}

///|
test "inline create and invalid write fields use exact authored keys" {
  let source = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"payload\":{\"Name\":\"example\"}}}}"
  let shapes = effect_mapping_rule_inputs(source, 4)
  let rules = bind_effect_mapping_rules(shapes, 17).unwrap()
  assert_eq(effect_mapping_rule_count(rules), 2)
  let foreign = source.replace(
    old="\"Name\":\"example\"",
    new="\"Other\":\"example\"",
  )
  let shapes = effect_mapping_rule_inputs(foreign, 4)
  let issue = bind_effect_mapping_rules(shapes, 20).unwrap_err()
  assert_eq(
    effect_mapping_rule_issue_kind(issue),
    Permission(@environment.InvalidRequest),
  )
  assert_eq(effect_mapping_rule_issue_stage(issue), 0)
  assert_eq(effect_mapping_rule_issue_effect(issue), "create")
}

///|
test "Effect selector and kind cannot borrow another Mapping rule" {
  let effects = "{\"update\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":{\"literal\":\"new\"}}}}}"
  let shapes = effect_mapping_rule_inputs(effects, 8)
  let issue = bind_effect_mapping_rules(shapes, 20).unwrap_err()
  assert_eq(
    effect_mapping_rule_issue_kind(issue),
    Permission(@environment.NoMatchingRule),
  )
  assert_eq(effect_mapping_rule_issue_effect(issue), "update")
}

///|
test "store update upsert and delete derive their authored rule dimensions" {
  let target = "\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\""
  let cases : Array[(String, String, String, String)] = [
    ("store", ",\"from\":{\"result\":\"r\"}", "none", "[\"Name\"]"),
    (
      "update", ",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":{\"literal\":\"x\"}}",
      "id", "[\"Name\"]",
    ),
    (
      "upsert", ",\"from\":{\"result\":\"r\"},\"key\":\"amount\",\"set\":{\"Name\":{\"literal\":\"x\"}}",
      "key", "[\"Name\"]",
    ),
    ("delete", ",\"ids\":[\"one\"]", "ids", "[]"),
  ]
  for (kind, suffix, selector, fields) in cases {
    let effects = "{\"member\":{\"" + kind + "\":{" + target + suffix + "}}}"
    let (checked, headers) = effect_binding_inputs(effects)
    let bindings = bind_effect_results(headers, checked, 10).unwrap()
    let rule = "[{\"effect_kind\":\"" +
      kind +
      "\",\"permissions\":[\"scope:" +
      kind +
      "\"],\"selector_class\":\"" +
      selector +
      "\",\"write_fields\":" +
      fields +
      "}]"
    let mappings = effect_mapping_shape_fixture_with_rules(rule)
    let shapes = bind_effect_mapping_shapes(
      bindings,
      mappings,
      effect_result_binding_count(bindings),
    ).unwrap()
    let rules = bind_effect_mapping_rules(shapes, 50).unwrap()
    assert_eq(effect_mapping_rule_count(rules), 2)
    let selected = effect_mapping_rule_selection(
      effect_mapping_rule_at(rules, 0).unwrap(),
    )
    assert_eq(@environment.mapping_permission_names(selected), ["scope:" + kind])
    assert_eq(@environment.mapping_permission_rule(selected).0, kind)
    assert_eq(@environment.mapping_permission_rule(selected).1, selector)
  }
}

///|
test "inline create cannot omit a required Mapping target field" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"payload\":{}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, 4).unwrap()
  let mappings = effect_mapping_shape_fixture_with_body(
    "[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[]}]",
    "[\"Name\"]", "amount",
  )
  let shapes = bind_effect_mapping_shapes(bindings, mappings, 2).unwrap()
  let issue = bind_effect_mapping_rules(shapes, 20).unwrap_err()
  assert_eq(effect_mapping_rule_issue_kind(issue), MissingRequiredField("Name"))
  assert_eq(effect_mapping_rule_issue_effect(issue), "create")
}

///|
test "result-backed create cannot use a missing Mapping source field" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, 4).unwrap()
  let mappings = effect_mapping_shape_fixture_with_body(
    "[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}]",
    "[]", "missing",
  )
  let shapes = bind_effect_mapping_shapes(bindings, mappings, 2).unwrap()
  let issue = bind_effect_mapping_rules(shapes, 20).unwrap_err()
  assert_eq(
    effect_mapping_rule_issue_kind(issue),
    MissingResultField("missing"),
  )
  assert_eq(effect_mapping_rule_issue_stage(issue), 0)
}

///|
test "Mapping rejects a direct Result source with incompatible target shape" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, 4).unwrap()
  let mappings = effect_mapping_shape_fixture_with_body(
    "[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}]",
    "[]",
    "amount",
    target_type="string",
  )
  let shapes = bind_effect_mapping_shapes(bindings, mappings, 2).unwrap()
  let issue = bind_effect_mapping_rules(shapes, 30).unwrap_err()
  assert_eq(
    effect_mapping_rule_issue_kind(issue),
    IncompatibleSourceType("Name"),
  )
  assert_eq(effect_mapping_rule_issue_stage(issue), 0)
}

///|
test "inline set Result field must fit its exact Mapping target type" {
  let effects = "{\"update\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":{\"field\":\"amount\"}}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, 8).unwrap()
  let rule = "[{\"effect_kind\":\"update\",\"permissions\":[\"scope:update\"],\"selector_class\":\"id\",\"write_fields\":[\"Name\"]}]"
  let compatible = effect_mapping_shape_fixture_with_body(rule, "[]", "amount")
  let shapes = bind_effect_mapping_shapes(bindings, compatible, 2).unwrap()
  assert_eq(
    effect_mapping_rule_count(bind_effect_mapping_rules(shapes, 50).unwrap()),
    2,
  )
  let incompatible = effect_mapping_shape_fixture_with_body(
    rule,
    "[]",
    "amount",
    target_type="string",
  )
  let shapes = bind_effect_mapping_shapes(bindings, incompatible, 2).unwrap()
  let issue = bind_effect_mapping_rules(shapes, 50).unwrap_err()
  assert_eq(
    effect_mapping_rule_issue_kind(issue),
    IncompatibleSourceType("Name"),
  )
}
