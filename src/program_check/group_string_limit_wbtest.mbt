///|
test "formal check retains owned string limits including guard-only parameter ceilings" {
  for
    (host, guard_text, maximum, binding) in [
      (None, "2", "2", "binding"),
      (None, "{\"$param\":\"n\"}", "1", "binding"),
      (Some(2), "2", "2", "currently_non_binding"),
      (Some(1), "2", "1", "currently_non_binding"),
      (Some(7), "2", "2", "binding"),
      (Some(7), "", "7", "absent"),
    ] {
    let programs : Array[CheckedProgram] = []
    let call = "{\"fn\":\"string_agg\",\"field\":\"text\",\"delimiter\":\",\",\"order_by\":[{\"id\":\"asc\"}]" +
      (if guard_text == "" { "" } else { ",\"max_bytes\":" + guard_text }) +
      "}"
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      parameters=true,
      string_limit=host,
      second_stage=true,
      through_check=true,
      checked_results=programs,
      producer_expression="'x'",
      second_steps="[{\"derive\":{\"text\":\"'x'\"}},{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"a~/b\":" +
        call +
        ",\"value\":" +
        call +
        "}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=3,
    )
    let program = programs[0]
    assert_eq(unit_group_string_limit_count(program, 0), Some(0))
    assert_eq(unit_group_string_limit_count(program, 1), Some(2))
    let limit = unit_group_string_limit_at(program, 1, 0).unwrap()
    assert_true(
      physical_equal(limit, unit_group_string_limit_at(program, 1, 0).unwrap()),
    )
    assert_true(
      (@context.group_string_limit_host(group_string_limit_selection(limit))
      is None) ==
      (host is None),
    )
    let claim = group_string_limit_claim(limit)
    assert_eq(
      @wire.limit_subject(claim),
      "unit:" +
      program.units[1].definition_cid +
      "#/steps/1/group/aggregates/a~0~1b/bytes",
    )
    let out = @encode.writer(100000, 10000, 100)
    @wire.emit_limit(claim, out)
    let text = @encode.finish(out)
    assert_true(text.contains("\"author_guard_binding\":\"" + binding + "\""))
    assert_true(text.contains("\"unit\":\"bytes\""))
    assert_true(text.contains("\"effective_max\":" + maximum))
    assert_eq(
      text.contains("\"law_id\":\"actql.guard.string-aggregate\""),
      guard_text != "",
    )
    let initial = IdentityBudget::{
      work: 100000000,
      bytes: 10000000,
      nodes: 1000000,
      depth: 100,
    }
    let budget = IdentityBudget::{ ..initial, }
    let _ = prepare_program_group_string_limits(
      program.units,
      requirements(program),
      budget,
    )
    let exact = IdentityBudget::{
      work: initial.work - budget.work,
      bytes: initial.bytes - budget.bytes,
      nodes: initial.nodes - budget.nodes,
      depth: 100,
    }
    let _ = prepare_program_group_string_limits(
      program.units,
      requirements(program),
      exact,
    )
    assert_eq(exact.work, 0)
    for kind in 0..<3 {
      let short = IdentityBudget::{
        work: initial.work - budget.work,
        bytes: initial.bytes - budget.bytes,
        nodes: initial.nodes - budget.nodes,
        depth: 100,
      }
      if kind == 0 {
        short.work -= 1
      } else if kind == 1 {
        short.bytes -= 1
      } else {
        short.nodes -= 1
      }
      let before = (short.work, short.bytes, short.nodes)
      let failed = try {
        let _ = prepare_program_group_string_limits(
          program.units,
          requirements(program),
          short,
        )
        false
      } catch {
        BudgetExceeded | Encoding(_) | PublicationHost(_) => true
        _ => false
      }
      assert_true(failed)
      assert_eq((short.work, short.bytes, short.nodes), before)
    }
    assert_true(unit_group_string_limit_at(program, 1, 2) is None)
    assert_true(unit_group_string_limit_count(program, -1) is None)
  }
}

///|
test "later string aggregate without a finite limit cannot publish a partial checked program" {
  let programs : Array[CheckedProgram] = []
  let failed = try {
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=programs,
      producer_expression="'x'",
      second_steps="[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"string_agg\",\"field\":\"value\",\"delimiter\":\",\",\"order_by\":[{\"id\":\"asc\"}]}}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
    false
  } catch {
    LocalConstructionFailure::Closure(
      ConstructionFailure::GroupStringLimits(MissingFiniteBound(_))
    ) => true
    _ => false
  }
  assert_true(failed)
  assert_eq(programs.length(), 0)
}
