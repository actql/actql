///|
fn effect_plan_rules(
  effect : String,
  kind : String,
  selector : String,
  write_fields? : String = "[\"Name\"]",
) -> EffectMappingRules {
  let (checked, headers) = effect_binding_inputs(effect)
  let bindings = bind_effect_results(headers, checked, 12).unwrap()
  let permission = "[{\"effect_kind\":\"" +
    kind +
    "\",\"permissions\":[\"scope:" +
    kind +
    "\"],\"selector_class\":\"" +
    selector +
    "\",\"write_fields\":" +
    write_fields +
    "}]"
  let shapes = bind_effect_mapping_shapes(
    bindings,
    effect_mapping_shape_fixture_with_rules(permission),
    effect_result_binding_count(bindings),
  ).unwrap()
  bind_effect_mapping_rules(shapes, 50).unwrap()
}

///|
fn effect_plan_rule(
  effect : String,
  kind : String,
  selector : String,
) -> EffectMappingRuleBinding {
  effect_mapping_rule_at(effect_plan_rules(effect, kind, selector), 0).unwrap()
}

///|
fn effect_plan_test_limits(max_bytes? : Int = 1024) -> EffectPlanIdentityLimits {
  { max_work: 20, max_fields: 10, max_bytes, max_nodes: 40, max_depth: 8, }
}

///|
test "Plan terminal selection retains the exact checked Result owner" {
  let update = "{\"member\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":{\"field\":\"amount\"}}}}}"
  let rules = effect_plan_rules(update, "update", "id")
  let terminal = match effect_plan_terminal_for_member(rules, 0, 1, 10) {
    Ok(Some(value)) => value
    Ok(None) => fail("missing checked Plan")
    Err(InvalidLimits) => fail("invalid Plan limits")
    Err(WorkLimit) => fail("Plan work limit")
    Err(InvalidMember) => fail("invalid Plan member")
    Err(MissingRule) => fail("missing Plan rule")
    Err(Terminal(_)) => fail("invalid Plan terminal")
  }
  assert_eq(effect_plan_terminal_source_result(terminal), "r")
  assert_true(
    physical_equal(
      effect_plan_terminal_rule(terminal),
      effect_mapping_rule_at(rules, 0).unwrap(),
    ),
  )
  assert_eq(
    effect_plan_terminal_for_member(rules, 0, 1, 0).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    effect_plan_terminal_for_member(rules, 0, 0, 10).unwrap_err(),
    Terminal(FieldLimit),
  )
  assert_eq(
    effect_plan_terminal_for_member(rules, 10, 1, 10).unwrap_err(),
    InvalidMember,
  )
}

///|
test "checked update lowers to an independently pinned AoA effect plan" {
  let common = "\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"}"
  let update = "{\"member\":{\"update\":{" +
    common +
    ",\"id\":\"amount\",\"set\":{\"Name\":{\"field\":\"amount\"}}}}}"
  let rule = effect_plan_rule(update, "update", "id")
  let terminal = prepare_effect_plan_terminal(rule, 1).unwrap().unwrap()
  assert_true(physical_equal(effect_plan_terminal_rule(terminal), rule))
  assert_eq(effect_plan_terminal_source_result(terminal), "r")
  let expected = "{\"output\":\"intent\",\"sources\":{\"r\":{\"sort\":\"relation\"}},\"steps\":[{\"id\":\"intent\",\"in\":[\"r\"],\"op\":\"EFFECT.plan\",\"params\":{\"entity\":\"connector://crm/account\",\"field_map\":{\"Name\":\"amount\"},\"op\":\"update\",\"selector\":\"byId\",\"selector_field\":\"amount\"}}],\"version\":\"aoa-pipeline/0.1\"}"
  let out = @encode.writer(1024, 40, 8)
  emit_effect_plan_pipeline(terminal, out)
  assert_eq(@encode.finish(out), expected)
  assert_eq(
    effect_plan_pipeline_cid(terminal, 1024, 40, 8),
    "sha256:fea978018b2bbacd9466aace2c629b7012bc106dade254480242d501d557351d",
  )
  assert_eq(prepare_effect_plan_terminal(rule, 0).unwrap_err(), FieldLimit)
}

///|
test "id and match share the plan but not the authored authority" {
  let common = "\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"}"
  let id = "{\"member\":{\"update\":{" +
    common +
    ",\"id\":\"amount\",\"set\":{\"Name\":{\"field\":\"amount\"}}}}}"
  let matched = "{\"member\":{\"update\":{" +
    common +
    ",\"match\":{\"target_field\":\"Id\",\"result_field\":\"amount\"},\"set\":{\"Name\":{\"field\":\"amount\"}}}}}"
  let first = prepare_effect_plan_terminal(
      effect_plan_rule(id, "update", "id"),
      1,
    )
    .unwrap()
    .unwrap()
  let second = prepare_effect_plan_terminal(
      effect_plan_rule(matched, "update", "match"),
      1,
    )
    .unwrap()
    .unwrap()
  assert_eq(
    effect_plan_pipeline_cid(first, 1024, 40, 8),
    effect_plan_pipeline_cid(second, 1024, 40, 8),
  )
  assert_true(
    prepare_effect_plan_terminal(effect_plan_rule(id, "update", "id"), -1).unwrap_err() ==
    InvalidLimits,
  )
}

///|
test "literal changes stay out of the upsert AoA field map" {
  let upsert = "{\"member\":{\"upsert\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"key\":\"amount\",\"set\":{\"Name\":{\"literal\":1}}}}}"
  let terminal = prepare_effect_plan_terminal(
      effect_plan_rule(upsert, "upsert", "key"),
      1,
    )
    .unwrap()
    .unwrap()
  let out = @encode.writer(1024, 40, 8)
  emit_effect_plan_pipeline(terminal, out)
  let wire = @encode.finish(out)
  assert_true(wire.contains("\"selector\":\"byExternalId\""))
  assert_true(wire.contains("\"selector_field\":\"amount\""))
  assert_false(wire.contains("field_map"))
  assert_false(wire.contains("literal"))
}

///|
test "checked Preview must carry the derived plan, not a supplied CID" {
  let update = "{\"member\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":{\"field\":\"amount\"}}}}}"
  let rules = effect_plan_rules(update, "update", "id")
  let good = checked_preview_test_identity(
    "member",
    "unused",
    include_second=false,
    first_kind="update",
    first_plan_cid=Some(
      "sha256:fea978018b2bbacd9466aace2c629b7012bc106dade254480242d501d557351d",
    ),
  )
  assert_true(
    check_effect_preview_plan_inventory(
      rules,
      0,
      good,
      effect_plan_test_limits(),
    )
    is Ok(_),
  )
  let missing = checked_preview_test_identity(
    "member",
    "unused",
    include_second=false,
    first_kind="update",
  )
  assert_eq(
    check_effect_preview_plan_inventory(
      rules,
      0,
      missing,
      effect_plan_test_limits(),
    ).unwrap_err(),
    MissingPlan("member"),
  )
  let foreign = checked_preview_test_identity(
    "member",
    "unused",
    include_second=false,
    first_kind="update",
    first_plan_cid=Some(checked_preview_test_cid("f")),
  )
  assert_eq(
    check_effect_preview_plan_inventory(
      rules,
      0,
      foreign,
      effect_plan_test_limits(),
    ).unwrap_err(),
    ForeignPlan("member"),
  )
  assert_eq(
    check_effect_preview_plan_inventory(
      rules,
      0,
      good,
      effect_plan_test_limits(max_bytes=10),
    ).unwrap_err(),
    OutputLimit,
  )
  assert_eq(
    check_effect_preview_plan_inventory(
      rules,
      -1,
      good,
      effect_plan_test_limits(),
    ).unwrap_err(),
    InvalidStage,
  )
}

///|
test "two member plans consume one aggregate identity budget" {
  let common = "\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"}"
  let effects = "{\"first\":{\"update\":{" +
    common +
    ",\"id\":\"amount\",\"set\":{\"Name\":{\"field\":\"amount\"}}}}," +
    "\"second\":{\"upsert\":{" +
    common +
    ",\"key\":\"amount\",\"set\":{\"Name\":{\"literal\":1}}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, 24).unwrap()
  let permissions = "[{\"effect_kind\":\"update\",\"permissions\":[\"scope:update\"],\"selector_class\":\"id\",\"write_fields\":[\"Name\"]},{\"effect_kind\":\"upsert\",\"permissions\":[\"scope:upsert\"],\"selector_class\":\"key\",\"write_fields\":[\"Name\"]}]"
  let shapes = bind_effect_mapping_shapes(
    bindings,
    effect_mapping_shape_fixture_with_rules(permissions),
    effect_result_binding_count(bindings),
  ).unwrap()
  let rules = bind_effect_mapping_rules(shapes, 100).unwrap()
  let first_plan = effect_plan_terminal_for_member(rules, 0, 1, 10)
    .unwrap()
    .unwrap()
  let second_plan = effect_plan_terminal_for_member(rules, 1, 1, 10)
    .unwrap()
    .unwrap()
  assert_eq(effect_plan_terminal_source_result(first_plan), "r")
  assert_eq(effect_plan_terminal_source_result(second_plan), "r")
  assert_true(
    !physical_equal(
      effect_plan_terminal_rule(first_plan),
      effect_plan_terminal_rule(second_plan),
    ),
  )
  let preview = checked_preview_test_identity(
    "first",
    "second",
    first_kind="update",
    second_kind="upsert",
    second_policy=Some("halt"),
    first_plan_cid=Some(
      "sha256:fea978018b2bbacd9466aace2c629b7012bc106dade254480242d501d557351d",
    ),
    second_plan_cid=Some(
      "sha256:6ca3a00b632500086fe612aee1bd119340543ff81c1966c0bec552cad6387662",
    ),
  )
  assert_true(
    check_effect_preview_plan_inventory(rules, 0, preview, {
      max_work: 30,
      max_fields: 2,
      max_bytes: 526,
      max_nodes: 80,
      max_depth: 8,
    })
    is Ok(_),
  )
  assert_eq(
    check_effect_preview_plan_inventory(rules, 0, preview, {
      max_work: 30,
      max_fields: 2,
      max_bytes: 525,
      max_nodes: 80,
      max_depth: 8,
    }).unwrap_err(),
    OutputLimit,
  )
}
