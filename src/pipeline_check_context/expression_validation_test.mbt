///|
fn validation_limits() -> ExpressionValidationLimits {
  {
    max_work: 1000000,
    max_text_bytes: 1000000,
    max_policy_nodes: 100,
    max_policy_depth: 10,
    max_requirements: 100,
  }
}

///|
fn validation_profile(component : String) -> String {
  capacity_profile(false).replace(
    old="\"version\":\"actql-capacity-host-policy/0.1\"}}",
    new="\"version\":\"actql-capacity-host-policy/0.1\"},\"text_time_evaluation\":" +
      component +
      "}",
  )
}

///|
fn valid_text_policy() -> String {
  (
    #|{"max_input_codepoints":1,"max_input_utf8_bytes":1,"max_output_bytes":1,"max_pattern_bytes":1,"max_replacements":1,"version":"actql-text-time-host-policy/0.1"}
  )
}

///|
fn validation_fixture(profile : String, active : Bool) -> SelectedPolicyContext {
  let (context, capacity) = selected_fixture(
    false,
    profile~,
    expression=if active {
      "if(TRUE, 'ok', regex_extract('a', '(a)', $n))"
    } else {
      "$n"
    },
  )
  bind_capacity_policy(
    context,
    capacity,
    max_work=1000000,
    max_text_bytes=1000000,
    max_policy_nodes=100,
  ).unwrap()
}

///|
test "expression validation retains staged occurrences, exact bindings and selected policy without discharge" {
  let selected = validation_fixture(
    validation_profile(valid_text_policy()),
    true,
  )
  let context = prepare_expression_validation(selected, validation_limits()).unwrap()
  assert_true(physical_equal(expression_validation_selected(context), selected))
  let text_time = expression_validation_text_time(context).unwrap()
  assert_true(
    physical_equal(
      @environment.text_time_environment(text_time),
      @environment.capacity_environment(selected_capacity(selected)),
    ),
  )
  // One local visit in the first stage, two in the second (including the first
  // producer). Each retains all three obligations in the unselected branch.
  assert_eq(expression_validation_count(context), 9)
  let stages = wired_stage_contexts(reconciled_wiring(policy_context(selected)))
  let mut profiles = 0
  let mut envelopes = 0
  let mut patterns = 0
  for i in 0..<9 {
    let site = expression_validation_at(context, i).unwrap()
    assert_true(physical_equal(validation_site_context(site), context))
    let (stage, index) = validation_site_location(site)
    assert_eq(stage, if i < 3 { 0 } else { 1 })
    assert_eq(index, if i < 3 { i } else { i - 3 })
    let requirement = validation_site_requirement(site)
    assert_eq(requirement.visit, if i < 6 { 0 } else { 1 })
    assert_eq(requirement.step, 0)
    let bound = stage_context_at(stages, stage).unwrap()
    let original = expression_requirement_at(parameter_context(bound), index).unwrap()
    assert_true(physical_equal(requirement.expression, original.expression))
    assert_eq(requirement.obligation.node_index, original.obligation.node_index)
    let visit = validation_site_parameters(site)
    let original_visit = parameter_visit_at(bound, requirement.visit).unwrap()
    assert_true(physical_equal(visit.collected, original_visit.collected))
    assert_true(
      physical_equal(visit.bound.unwrap(), original_visit.bound.unwrap()),
    )
    assert_true(
      physical_equal(
        @references.bound_index(visit.bound.unwrap()),
        @parameter_slots.index(visit.collected),
      ),
    )
    assert_true(
      @typing.node_at(requirement.expression, requirement.obligation.node_index)
      is Some(_),
    )
    match requirement.obligation.kind {
      ProfileAdmission(name) => {
        assert_eq(name, "actql-text-time/0.1")
        profiles += 1
      }
      HostEnvelope => envelopes += 1
      PatternValidation(name) => {
        assert_eq(name, "regex_extract")
        patterns += 1
      }
    }
  }
  assert_eq((profiles, envelopes, patterns), (3, 3, 3))
  assert_true(expression_validation_at(context, -1) is None)
  assert_true(expression_validation_at(context, 9) is None)
  let other = prepare_expression_validation(
    validation_fixture(validation_profile(valid_text_policy()), true),
    validation_limits(),
  ).unwrap()
  assert_false(
    physical_equal(
      validation_site_context(expression_validation_at(other, 0).unwrap()),
      context,
    ),
  )
  assert_false(
    physical_equal(
      @references.bound_values(
        validation_site_parameters(expression_validation_at(other, 0).unwrap()).bound.unwrap(),
      ),
      @references.bound_values(
        validation_site_parameters(
          expression_validation_at(context, 0).unwrap(),
        ).bound.unwrap(),
      ),
    ),
  )
}

///|
test "expression validation shares cumulative budgets and retains unresolved missing policy" {
  for present in [false, true] {
    let selected = validation_fixture(
      if present {
        validation_profile(valid_text_policy())
      } else {
        capacity_profile(false)
      },
      true,
    )
    let result = prepare_expression_validation(selected, validation_limits()).unwrap()
    assert_eq(expression_validation_count(result), 9)
    assert_eq(expression_validation_text_time(result) is Some(_), present)
    let before = selected_policy_usage(selected)
    let (bytes, nodes) = match expression_validation_text_time(result) {
      Some(policy) => @environment.text_time_usage(policy)
      None => (0, 0)
    }
    let used = expression_validation_usage(result)
    assert_eq(used, {
      work: before.work + 1 + nodes + 2 + 9,
      text_bytes: before.text_bytes + bytes,
      policy_nodes: before.policy_nodes + nodes,
      local_input_nodes: before.local_input_nodes,
    })
    let exact : ExpressionValidationLimits = {
      max_work: used.work,
      max_text_bytes: used.text_bytes,
      max_policy_nodes: used.policy_nodes,
      max_policy_depth: if present {
        1
      } else {
        0
      },
      max_requirements: 9,
    }
    assert_true(prepare_expression_validation(selected, exact) is Ok(_))
    for
      short in [
        { ..exact, max_work: exact.max_work - 1, },
        { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
        { ..exact, max_policy_nodes: exact.max_policy_nodes - 1, },
        { ..exact, max_requirements: 8, },
      ] {
      assert_true(
        prepare_expression_validation(selected, short) is Err(BudgetExceeded),
      )
    }
    if present {
      assert_true(
        prepare_expression_validation(selected, {
          ..exact,
          max_policy_depth: 0,
        })
        is Err(BudgetExceeded),
      )
    }
    for
      invalid in [
        { ..exact, max_work: -1, },
        { ..exact, max_text_bytes: -1, },
        { ..exact, max_policy_nodes: -1, },
        { ..exact, max_policy_depth: -1, },
        { ..exact, max_requirements: -1, },
      ] {
      assert_true(
        prepare_expression_validation(selected, invalid) is Err(InvalidLimits),
      )
    }
  }
}

///|
test "expression validation validates unused text-time components and creates no defaults" {
  for
    component in [
      "null",
      "[]",
      "{}",
      valid_text_policy().replace(
        old="\"max_pattern_bytes\":1",
        new="\"max_pattern_bytes\":0",
      ),
    ] {
    let selected = validation_fixture(validation_profile(component), false)
    assert_true(
      prepare_expression_validation(selected, validation_limits())
      is Err(TextTime(_)),
    )
  }
  for
    profile in [
      capacity_profile(false),
      validation_profile(valid_text_policy()),
    ] {
    let result = prepare_expression_validation(
      validation_fixture(profile, false),
      validation_limits(),
    ).unwrap()
    assert_eq(expression_validation_count(result), 0)
  }
}
