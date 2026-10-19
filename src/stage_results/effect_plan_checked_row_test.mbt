///|
fn checked_plan_fixture(
  literal? : Bool = false,
) -> (EffectPlanTerminal, EffectMappingLiterals, @value.CheckedValue) {
  let assigned = if literal {
    "{\"literal\":9}"
  } else {
    "{\"field\":\"amount\"}"
  }
  let rules = effect_plan_rules(
    "{\"member\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"Name\":" +
    assigned +
    "}}}}",
    "update",
    "id",
  )
  let terminal = effect_plan_terminal_for_member(rules, 0, 10, 100)
    .unwrap()
    .unwrap()
  let literals = admit_effect_mapping_literals(
    rules,
    effect_mapping_literal_limits(work=100),
  ).unwrap()
  let binding = effect_mapping_shape_effect(
    effect_mapping_rule_effect(effect_plan_terminal_rule(terminal)),
  )
  let result = effect_result_binding_result(binding).unwrap()
  let contract = @schema.lookup_reference(
      @results.output_schema(result),
      "amount",
    ).unwrap().contract
  (terminal, literals, @value.checked_number_value(7, contract).unwrap())
}

///|
test "checked Mapping row preserves original values literals and legacy proposal bytes" {
  for literal in [false, true] {
    let (terminal, literals, original) = checked_plan_fixture(literal~)
    let reads = Ref(0)
    let reader_arguments_valid = Ref(true)
    let row = project_effect_plan_checked_row(
      terminal,
      literals,
      0,
      fn(name, remaining, values) {
        if name != "amount" || remaining <= 0 || values.max_nodes <= 0 {
          reader_arguments_valid.val = false
          return None
        }
        reads.val += 1
        Some((original, 1, 1, 0))
      },
      10,
      10000,
      { max_nodes: 10, max_depth: 4, max_text_bytes: 100, },
    ).unwrap()
    assert_true(reader_arguments_valid.val)
    assert_true(physical_equal(effect_plan_checked_row_selector(row), original))
    let (target, value) = effect_plan_checked_row_field_at(row, 0).unwrap()
    assert_eq(target, "Name")
    assert_eq(effect_plan_checked_row_field_count(row), 1)
    assert_true(effect_plan_checked_row_field_at(row, 1) is None)
    assert_eq(reads.val, if literal { 1 } else { 2 })
    if literal {
      let expected = effect_mapping_literal_value(
        effect_mapping_literal_at(literals, 0).unwrap(),
      )
      guard expected is Written(expected) else {
        fail("missing original literal")
      }
      assert_true(physical_equal(value, expected))
    } else {
      assert_true(physical_equal(value, original))
    }
    let legacy = project_effect_plan_row(
      terminal,
      effect_plan_test_row("{\"amount\":7}"),
      0,
      10,
      100,
    ).unwrap()
    assert_eq(
      effect_plan_checked_row_changes_wire(row, 1024, 100, 10).unwrap(),
      effect_plan_row_intended_changes_wire(
        legacy, literals, 10, 100, 1024, 100, 10,
      ).unwrap(),
    )
  }
}

///|
test "checked Mapping row rejects equal foreign contracts and literal owners before publication" {
  let (terminal, literals, original) = checked_plan_fixture()
  let foreign = @value.checked_number_value(
    7,
    @contract.primitive(NumberType, nullable=false),
  ).unwrap()
  assert_true(
    project_effect_plan_checked_row(
      terminal,
      literals,
      0,
      (_, _, _) => Some((foreign, 1, 1, 0)),
      10,
      10000,
      { max_nodes: 10, max_depth: 4, max_text_bytes: 100, },
    )
    is Err(ForeignSourceContract("amount")),
  )
  let (_, foreign_literals, _) = checked_plan_fixture()
  let reads = Ref(0)
  assert_true(
    project_effect_plan_checked_row(
      terminal,
      foreign_literals,
      0,
      fn(_, _, _) {
        reads.val += 1
        Some((original, 1, 1, 0))
      },
      10,
      10000,
      { max_nodes: 10, max_depth: 4, max_text_bytes: 100, },
    )
    is Err(ForeignLiterals),
  )
  assert_eq(reads.val, 0)
}

///|
test "checked Mapping row shares the original finite work and value ceilings" {
  let (terminal, literals, original) = checked_plan_fixture()
  let reads = Ref(0)
  let read = fn(_ : String, _ : Int, values : @value.Limits) {
    reads.val += 1
    if values.max_nodes == 0 {
      None
    } else {
      Some((original, 1, 1, 0))
    }
  }
  assert_true(
    project_effect_plan_checked_row(terminal, literals, 0, read, 10, 0, {
      max_nodes: 10,
      max_depth: 4,
      max_text_bytes: 100,
    })
    is Err(WorkLimit),
  )
  assert_eq(reads.val, 0)
  assert_true(
    project_effect_plan_checked_row(terminal, literals, 0, read, 0, 10000, {
      max_nodes: 10,
      max_depth: 4,
      max_text_bytes: 100,
    })
    is Err(FieldLimit),
  )
  assert_eq(reads.val, 0)
  assert_true(
    project_effect_plan_checked_row(terminal, literals, 0, read, 10, 10000, {
      max_nodes: 1,
      max_depth: 4,
      max_text_bytes: 100,
    })
    is Err(MissingSourceField("amount")),
  )
  assert_eq(reads.val, 2)
  assert_true(
    project_effect_plan_checked_row(
      terminal,
      literals,
      0,
      (_, _, _) => Some((original, 0, 1, 0)),
      10,
      10000,
      { max_nodes: 10, max_depth: 4, max_text_bytes: 100, },
    )
    is Err(InvalidReadUsage),
  )
}
