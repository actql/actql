///|
test "window string limits retain their byte scope and exact bound selection" {
  for
    (host, authored, maximum, binding) in [
      (None, "2", 2L, "binding"),
      (Some(1), "2", 1L, "currently_non_binding"),
      (Some(2), "2", 2L, "currently_non_binding"),
      (Some(7), "", 7L, "absent"),
      (None, "{\"$param\":\"n\"}", 1L, "binding"),
    ] {
    let programs : Array[CheckedProgram] = []
    let call = "{\"fn\":\"string_agg\",\"field\":\"text\",\"delimiter\":\",\",\"order_by\":[{\"id\":\"asc\"}]" +
      (if authored == "" { "" } else { ",\"max_bytes\":" + authored }) +
      "}"
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      tea=true,
      parameters=true,
      string_limit=host,
      producer_expression="'x'",
      second_steps="[{\"derive\":{\"text\":\"'x'\"}},{\"row_window\":{\"time\":\"id\",\"kind\":\"fixed\",\"size\":10}},{\"window_group\":{\"by\":[\"id\"],\"aggregates\":{\"a~/b\":" +
        call +
        ",\"value\":" +
        call +
        "}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=3,
    )
    let p = programs[0]
    assert_eq(unit_group_string_limit_count(p, 1), Some(2))
    assert_eq(unit_group_limit_count(p, 1), Some(0))
    let limit = unit_group_string_limit_at(p, 1, 0).unwrap()
    assert_true(
      physical_equal(limit, unit_group_string_limit_at(p, 1, 0).unwrap()),
    )
    let source = group_string_limit_source(limit)
    let selected = group_string_limit_selection(limit)
    assert_eq(@context.group_string_limit_maximum(selected), maximum)
    assert_eq(
      @context.group_string_limit_host(selected) is Some(_),
      host is Some(_),
    )
    assert_eq(
      @wire.limit_subject(group_string_limit_claim(limit)),
      "unit:" +
      unit_definition_cid(p, 1).unwrap() +
      "#/steps/2/window_group/aggregates/a~0~1b/bytes",
    )
    let out = @encode.writer(100000, 10000, 100)
    @wire.emit_limit(group_string_limit_claim(limit), out)
    let text = @encode.finish(out)
    assert_true(text.contains("\"unit\":\"bytes\""))
    assert_true(text.contains("\"author_guard_binding\":\"" + binding + "\""))
    assert_false(text.contains("/group/aggregates/"))
    if authored == "2" {
      let fixed = {
        ..source,
        operation: {
          ..source.operation,
          unit_definition_cid: "sha256:" + "0".repeat(64),
        },
      }
      // Independently authored canonical preimage hashed with Node SHA-256.
      assert_eq(
        @wire.cid(
          emit_group_guard_witness(fixed, 2L, {
            work: 100000,
            bytes: 10000,
            nodes: 1000,
            depth: 100,
          }),
        ),
        "sha256:f41b4cfebc503fa37c0e119fb1ac422dab85d403e8e97dee84b09909f19eeed6",
      )
    }
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let _ = prepare_program_group_string_limits(
      p.units,
      requirements(p),
      budget,
    )
    let used = (
      10000000 - budget.work,
      1000000 - budget.bytes,
      100000 - budget.nodes,
    )
    let exact = IdentityBudget::{
      work: used.0,
      bytes: used.1,
      nodes: used.2,
      depth: 100,
    }
    let _ = prepare_program_group_string_limits(p.units, requirements(p), exact)
    assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
    for
      short in [
        IdentityBudget::{
          work: used.0 - 1,
          bytes: used.1,
          nodes: used.2,
          depth: 100,
        },
        IdentityBudget::{
          work: used.0,
          bytes: used.1 - 1,
          nodes: used.2,
          depth: 100,
        },
        IdentityBudget::{
          work: used.0,
          bytes: used.1,
          nodes: used.2 - 1,
          depth: 100,
        },
      ] {
      let before = (short.work, short.bytes, short.nodes)
      try
        prepare_program_group_string_limits(p.units, requirements(p), short)
      catch {
        _ => ()
      } noraise {
        _ => fail("partial window string limits escaped the budget")
      }
      assert_eq((short.work, short.bytes, short.nodes), before)
    }
  }
}

///|
test "window string grouping without a finite bound cannot return a partial program" {
  let programs : Array[CheckedProgram] = []
  try
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      tea=true,
      producer_expression="'x'",
      second_steps="[{\"row_window\":{\"time\":\"id\",\"kind\":\"fixed\",\"size\":10}},{\"window_group\":{\"by\":[\"id\"],\"aggregates\":{\"value\":{\"fn\":\"string_agg\",\"field\":\"value\",\"delimiter\":\",\",\"order_by\":[{\"id\":\"asc\"}]}}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
  catch {
    Closure(GroupStringLimits(MissingFiniteBound(_))) => ()
    error => raise error
  } noraise {
    _ => fail("missing window string bound was accepted")
  }
  assert_eq(programs.length(), 0)
}
