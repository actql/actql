///|
fn create_row_fixture(
  mapping : String,
  required? : String = "[]",
) -> (EffectCreateRowTerminal, EffectMappingLiterals) {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"}}}}"
  let permission = "[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}]"
  let rules = effect_mapping_literal_rules(
    effects,
    effect_mapping_shape_fixture_with_body(
      permission,
      required,
      "amount",
      row_mapping=mapping,
    ),
  )
  let terminal = effect_create_row_terminal_for_member(rules, 0, 1, 50)
    .unwrap()
    .unwrap()
  let literals = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(work=20, nodes=10, text=100),
  ).unwrap()
  (terminal, literals)
}

///|
test "checked create row mapping projects exact values before Preview" {
  let (terminal, literals) = create_row_fixture(
    "{\"Name\":{\"field\":\"amount\",\"null_behavior\":\"reject\"}}",
  )
  assert_eq(effect_create_row_terminal_source_result(terminal), "r")
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal,
      literals,
      effect_plan_test_row("{\"amount\":7}"),
      1,
      20,
      100,
      10,
      4,
    ).unwrap(),
    "{\"state\":\"present\",\"value\":{\"Name\":7}}",
  )
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal,
      literals,
      effect_plan_test_row("{\"other\":7}"),
      1,
      20,
      100,
      10,
      4,
    ).unwrap_err(),
    MissingSourceField("amount"),
  )
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal,
      literals,
      effect_plan_test_row("{\"amount\":7}"),
      1,
      2,
      100,
      10,
      4,
    ).unwrap_err(),
    WorkLimit,
  )
}

///|
test "create row null policy and admitted literals remain distinct" {
  let null = effect_plan_test_row("{\"amount\":null}")
  let (reject, literals) = create_row_fixture(
    "{\"Name\":{\"field\":\"amount\",\"null_behavior\":\"reject\"}}",
  )
  assert_eq(
    effect_create_row_intended_changes_wire(
      reject, literals, null, 1, 20, 100, 10, 4,
    ).unwrap_err(),
    RejectedNull("Name"),
  )
  let (omit, literals) = create_row_fixture(
    "{\"Name\":{\"field\":\"amount\",\"null_behavior\":\"omit\"}}",
  )
  assert_eq(
    effect_create_row_intended_changes_wire(
      omit, literals, null, 1, 20, 100, 10, 4,
    ).unwrap(),
    "{\"state\":\"present\",\"value\":{}}",
  )
  let (write_null, literals) = create_row_fixture(
    "{\"Name\":{\"field\":\"amount\",\"null_behavior\":\"write_null\"}}",
  )
  assert_eq(
    effect_create_row_intended_changes_wire(
      write_null, literals, null, 1, 20, 100, 10, 4,
    ).unwrap(),
    "{\"state\":\"present\",\"value\":{\"Name\":null}}",
  )
  let (literal, literals) = create_row_fixture(
    "{\"Name\":{\"literal\":7,\"null_behavior\":\"reject\"}}",
  )
  assert_eq(
    effect_create_row_intended_changes_wire(
      literal,
      literals,
      effect_plan_test_row("{\"amount\":null}"),
      1,
      20,
      100,
      10,
      4,
    ).unwrap(),
    "{\"state\":\"present\",\"value\":{\"Name\":7}}",
  )
  assert_eq(
    effect_create_row_intended_changes_wire(
      write_null, literals, null, 1, 20, 100, 10, 4,
    ).unwrap_err(),
    ForeignLiterals,
  )
}
