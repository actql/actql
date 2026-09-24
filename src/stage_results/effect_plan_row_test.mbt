///|
fn effect_plan_test_row(wire : String) -> @json.CanonicalValue {
  let parsed = @source.parse_json(wire, {
    max_input_bytes: 1024,
    max_nodes: 32,
    max_depth: 4,
  }).unwrap()
  @json.from_source(parsed, 32, 4, 1024) catch {
    _ => abort("Expected Result row fixture")
  }
}

///|
test "checked Effect plan projects one source row with bounded work" {
  let effect = "{\"member\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":{\"field\":\"amount\"}}}}}"
  let terminal = prepare_effect_plan_terminal(
      effect_plan_rule(effect, "update", "id"),
      1,
    )
    .unwrap()
    .unwrap()
  let row = effect_plan_test_row("{\"amount\":7,\"unused\":null}")
  let projected = project_effect_plan_row(terminal, row, 3, 1, 6).unwrap()
  assert_true(physical_equal(effect_plan_row_terminal(projected), terminal))
  assert_eq(effect_plan_row_source_index(projected), 3)
  assert_eq(
    @json.stringify_value(effect_plan_row_selector(projected), 32, 4, 2),
    "7",
  )
  assert_eq(effect_plan_row_field_count(projected), 1)
  let (name, value) = effect_plan_row_field_at(projected, 0).unwrap()
  assert_eq(name, "Name")
  assert_eq(@json.stringify_value(value, 32, 4, 2), "7")
  assert_true(effect_plan_row_field_at(projected, 1) is None)
  assert_eq(
    project_effect_plan_row(terminal, row, 3, 0, 6).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    project_effect_plan_row(terminal, row, 3, 1, 5).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    project_effect_plan_row(terminal, row, -1, 1, 6).unwrap_err(),
    InvalidLimits,
  )
}

///|
test "Effect plan never invents missing selector or mapped source values" {
  let effect = "{\"member\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":{\"field\":\"amount\"}}}}}"
  let terminal = prepare_effect_plan_terminal(
      effect_plan_rule(effect, "update", "id"),
      1,
    )
    .unwrap()
    .unwrap()
  assert_eq(
    project_effect_plan_row(
      terminal,
      effect_plan_test_row("{\"other\":7}"),
      0,
      1,
      4,
    ).unwrap_err(),
    MissingSelector,
  )
  assert_eq(
    project_effect_plan_row(terminal, effect_plan_test_row("[7]"), 0, 1, 4).unwrap_err(),
    InvalidRow,
  )
  let null_row = project_effect_plan_row(
    terminal,
    effect_plan_test_row("{\"amount\":null}"),
    0,
    1,
    4,
  ).unwrap()
  let (_, null_value) = effect_plan_row_field_at(null_row, 0).unwrap()
  assert_eq(@json.stringify_value(null_value, 32, 4, 4), "null")
}

///|
test "checked selector and mapped source remain distinct row obligations" {
  let effect = "{\"member\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"ref\",\"set\":{\"Name\":{\"field\":\"amount\"}}}}}"
  let (checked, headers) = effect_binding_inputs(
    effect,
    reference_nullable=Some(false),
  )
  let bindings = bind_effect_results(headers, checked, 12).unwrap()
  let rules = "[{\"effect_kind\":\"update\",\"permissions\":[\"scope:update\"],\"selector_class\":\"id\",\"write_fields\":[\"Name\"]}]"
  let shapes = bind_effect_mapping_shapes(
    bindings,
    effect_mapping_shape_fixture_with_rules(rules),
    effect_result_binding_count(bindings),
  ).unwrap()
  let admitted = bind_effect_mapping_rules(shapes, 50).unwrap()
  let terminal = prepare_effect_plan_terminal(
      effect_mapping_rule_at(admitted, 0).unwrap(),
      1,
    )
    .unwrap()
    .unwrap()
  assert_eq(
    project_effect_plan_row(
      terminal,
      effect_plan_test_row("{\"ref\":\"record-1\"}"),
      0,
      1,
      4,
    ).unwrap_err(),
    MissingSourceField("amount"),
  )
}
