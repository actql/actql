///|
fn explicit_create_values_bindings(
  values : String,
  amount_nullable? : Bool = false,
) -> Result[EffectResultBindings, EffectResultBindingIssue] {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"values\":" +
    values +
    "}}}"
  let (checked, headers) = effect_binding_inputs(effects, amount_nullable~)
  bind_effect_results(headers, checked, 20)
}

///|
fn explicit_create_values_rules(
  values : String,
  required? : String = "[]",
  amount_nullable? : Bool = false,
  target_nullable? : Bool = true,
  permission_fields? : String = "[\"Name\"]",
) -> Result[EffectMappingRules, EffectMappingRuleIssue] {
  let bindings = explicit_create_values_bindings(values, amount_nullable~).unwrap()
  let mappings = effect_mapping_shape_fixture_with_body(
    "[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":" +
    permission_fields +
    "}]",
    required,
    "not_in_selected_input",
    target_nullable~,
  )
  let shapes = bind_effect_mapping_shapes(bindings, mappings, 10).unwrap()
  bind_effect_mapping_rules(shapes, 200)
}

///|
test "explicit create values retain the original Mapping without requiring its unused row source" {
  let rules = explicit_create_values_rules("{\"Name\":{\"field\":\"amount\"}}").unwrap()
  let rule = effect_mapping_rule_at(rules, 0).unwrap()
  assert_true(effect_mapping_rule_row_fields(rule) is None)
  let mapping = effect_mapping_shape_contract(effect_mapping_rule_effect(rule))
  let original_rows = @environment.check_mapping_row_fields(mapping, 100).unwrap()
  assert_eq(
    @environment.mapping_row_fields_source_at(original_rows, 0),
    Some(("Name", Some("not_in_selected_input"))),
  )
  let literals = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(),
  ).unwrap()
  let terminal = effect_create_row_terminal_for_member(rules, 0, 1, 100)
    .unwrap()
    .unwrap()
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal,
      literals,
      effect_plan_test_row("{\"amount\":7}"),
      1,
      100,
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
      effect_plan_test_row("{}"),
      1,
      100,
      100,
      10,
      4,
    ).unwrap_err(),
    MissingSourceField("amount"),
  )
}

///|
test "explicit create values bind field contracts before any Preview" {
  assert_eq(
    effect_result_binding_issue_kind(
      explicit_create_values_bindings("{\"Name\":{\"field\":\"missing\"}}").unwrap_err(),
    ),
    MissingField,
  )
  assert_eq(
    effect_mapping_rule_issue_kind(
      explicit_create_values_rules(
        "{\"Name\":{\"field\":\"amount\"}}",
        amount_nullable=true,
        target_nullable=false,
      ).unwrap_err(),
    ),
    IncompatibleSourceType("Name"),
  )
  assert_true(
    explicit_create_values_rules("{\"Id\":{\"field\":\"amount\"}}") is Err(_),
  )
}

///|
test "explicit create literals use the same checked value and original rule" {
  let rules = explicit_create_values_rules("{\"Name\":{\"literal\":9}}").unwrap()
  let literals = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(),
  ).unwrap()
  assert_eq(effect_mapping_literal_count(literals), 2)
  assert_eq(
    effect_mapping_literal_origin(
      effect_mapping_literal_at(literals, 0).unwrap(),
    ),
    InlineCreate,
  )
  let terminal = effect_create_row_terminal_for_member(rules, 0, 1, 100)
    .unwrap()
    .unwrap()
  let row = effect_plan_test_row("{\"amount\":7}")
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal, literals, row, 1, 100, 100, 10, 4,
    ).unwrap(),
    "{\"state\":\"present\",\"value\":{\"Name\":9}}",
  )
  let foreign = admit_effect_mapping_literals(
    explicit_create_values_rules("{\"Name\":{\"literal\":9}}").unwrap(),
    effect_mapping_literal_limits(),
  ).unwrap()
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal, foreign, row, 1, 100, 100, 10, 4,
    ).unwrap_err(),
    ForeignLiterals,
  )
  assert_eq(
    effect_mapping_literal_issue_kind(
      admit_effect_mapping_literals(
        explicit_create_values_rules("{\"Name\":{\"literal\":\"wrong\"}}").unwrap(),
        effect_mapping_literal_limits(),
      ).unwrap_err(),
    ),
    IncompatibleLiteral("Name"),
  )
}

///|
test "explicit create omission is not null or the original Mapping default" {
  assert_eq(
    effect_mapping_rule_issue_kind(
      explicit_create_values_rules("{}").unwrap_err(),
    ),
    Permission(@environment.NoMatchingRule),
  )
  let rules = explicit_create_values_rules("{}", permission_fields="[]").unwrap()
  let terminal = effect_create_row_terminal_for_member(rules, 0, 0, 100)
    .unwrap()
    .unwrap()
  let literals = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(),
  ).unwrap()
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal,
      literals,
      effect_plan_test_row("{}"),
      0,
      100,
      100,
      10,
      4,
    ).unwrap(),
    "{\"state\":\"present\",\"value\":{}}",
  )
  assert_eq(
    effect_mapping_rule_issue_kind(
      explicit_create_values_rules("{}", required="[\"Name\"]").unwrap_err(),
    ),
    MissingRequiredField("Name"),
  )
  let rules = explicit_create_values_rules("{\"Name\":{\"literal\":null}}").unwrap()
  let terminal = effect_create_row_terminal_for_member(rules, 0, 1, 100)
    .unwrap()
    .unwrap()
  let literals = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(),
  ).unwrap()
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal,
      literals,
      effect_plan_test_row("{}"),
      1,
      100,
      100,
      10,
      4,
    ).unwrap(),
    "{\"state\":\"present\",\"value\":{\"Name\":null}}",
  )
}

///|
test "explicit create projection retains finite field work and output limits" {
  let rules = explicit_create_values_rules("{\"Name\":{\"field\":\"amount\"}}").unwrap()
  assert_eq(
    effect_create_row_terminal_for_member(rules, 0, 0, 100).unwrap_err(),
    Terminal(FieldLimit),
  )
  let terminal = effect_create_row_terminal_for_member(rules, 0, 1, 100)
    .unwrap()
    .unwrap()
  let literals = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(),
  ).unwrap()
  let row = effect_plan_test_row("{\"amount\":7}")
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal, literals, row, 1, 0, 100, 10, 4,
    ).unwrap_err(),
    WorkLimit,
  )
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal, literals, row, 1, 100, 2, 10, 4,
    ).unwrap_err(),
    OutputLimit,
  )
}

///|
test "explicit create source null uses its target Contract rather than unselected Mapping defaults" {
  let rules = explicit_create_values_rules(
    "{\"Name\":{\"field\":\"amount\"}}",
    amount_nullable=true,
  ).unwrap()
  let terminal = effect_create_row_terminal_for_member(rules, 0, 1, 100)
    .unwrap()
    .unwrap()
  let literals = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(),
  ).unwrap()
  // The retained original row mapping has reject, and references another
  // source field. Neither is silently applied to this explicit assignment.
  assert_eq(
    effect_create_row_intended_changes_wire(
      terminal,
      literals,
      effect_plan_test_row("{\"amount\":null}"),
      1,
      100,
      100,
      10,
      4,
    ).unwrap(),
    "{\"state\":\"present\",\"value\":{\"Name\":null}}",
  )
}
