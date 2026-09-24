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

///|
test "checked Plan changes merge only same-owner literals and bounded rows" {
  let effect = "{\"member\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":{\"literal\":5}}}}}"
  let rules = effect_plan_rules(effect, "update", "id")
  let admitted = admit_effect_mapping_literals(rules, {
    max_work: 50,
    max_value_nodes: 20,
    max_value_depth: 4,
    max_value_text_bytes: 100,
  }).unwrap()
  let terminal = prepare_effect_plan_terminal(
      effect_mapping_rule_at(rules, 0).unwrap(),
      1,
    )
    .unwrap()
    .unwrap()
  assert_eq(effect_mapping_literal_count(admitted), 2)
  assert_true(
    physical_equal(
      effect_mapping_literal_rule(
        effect_mapping_literal_at(admitted, 0).unwrap(),
      ),
      effect_plan_terminal_rule(terminal),
    ),
  )
  let row = project_effect_plan_row(
    terminal,
    effect_plan_test_row("{\"amount\":7}"),
    0,
    1,
    2,
  ).unwrap()
  let expected = "{\"state\":\"present\",\"value\":{\"Name\":5}}"
  assert_eq(
    effect_plan_row_intended_changes_wire(
      row,
      admitted,
      1,
      6,
      expected.length(),
      4,
      2,
    ),
    Ok(expected),
  )
  assert_eq(
    effect_plan_row_intended_changes_wire(
      row,
      admitted,
      1,
      5,
      expected.length(),
      4,
      2,
    ).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    effect_plan_row_intended_changes_wire(
      row,
      admitted,
      0,
      6,
      expected.length(),
      4,
      2,
    ).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    effect_plan_row_intended_changes_wire(
      row,
      admitted,
      1,
      6,
      expected.length() - 1,
      4,
      2,
    ).unwrap_err(),
    OutputLimit,
  )
  let foreign = admit_effect_mapping_literals(
    effect_plan_rules(effect, "update", "id"),
    {
      max_work: 50,
      max_value_nodes: 20,
      max_value_depth: 4,
      max_value_text_bytes: 100,
    },
  ).unwrap()
  assert_eq(
    effect_plan_row_intended_changes_wire(
      row,
      foreign,
      1,
      6,
      expected.length(),
      4,
      2,
    ).unwrap_err(),
    ForeignLiterals,
  )
}

///|
test "checked Plan row changes retain projected value and null" {
  let effect = "{\"member\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":{\"field\":\"amount\"}}}}}"
  let rules = effect_plan_rules(effect, "update", "id")
  let admitted = admit_effect_mapping_literals(rules, {
    max_work: 50,
    max_value_nodes: 20,
    max_value_depth: 4,
    max_value_text_bytes: 100,
  }).unwrap()
  let terminal = prepare_effect_plan_terminal(
      effect_mapping_rule_at(rules, 0).unwrap(),
      1,
    )
    .unwrap()
    .unwrap()
  for
    (source, expected) in [
      ("{\"amount\":7}", "{\"state\":\"present\",\"value\":{\"Name\":7}}"),
      ("{\"amount\":null}", "{\"state\":\"present\",\"value\":{\"Name\":null}}"),
    ] {
    let row = project_effect_plan_row(
      terminal,
      effect_plan_test_row(source),
      0,
      1,
      4,
    ).unwrap()
    assert_eq(
      effect_plan_row_intended_changes_wire(
        row,
        admitted,
        1,
        4,
        expected.length(),
        4,
        2,
      ).unwrap(),
      expected,
    )
  }
}

///|
test "checked delete Plan has no invented intended payload" {
  let effect = "{\"member\":{\"delete\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\"}}}"
  let rules = effect_plan_rules(effect, "delete", "id", write_fields="[]")
  let admitted = admit_effect_mapping_literals(rules, {
    max_work: 50,
    max_value_nodes: 20,
    max_value_depth: 4,
    max_value_text_bytes: 100,
  }).unwrap()
  let terminal = prepare_effect_plan_terminal(
      effect_mapping_rule_at(rules, 0).unwrap(),
      0,
    )
    .unwrap()
    .unwrap()
  let row = project_effect_plan_row(
    terminal,
    effect_plan_test_row("{\"amount\":7}"),
    0,
    0,
    2,
  ).unwrap()
  assert_eq(
    effect_plan_row_intended_changes_wire(row, admitted, 0, 2, 26, 2, 1),
    Ok("{\"state\":\"not_applicable\"}"),
  )
}
