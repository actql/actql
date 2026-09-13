///|
test "window array limits use a distinct subject and authored guard preimage" {
  for
    (kind, expected) in [
      (
        "group", "sha256:da53a7b146c7872f437d41a62c9d6b8326a02e4a32027f8427c2137d5ec2c93b",
      ),
      (
        "window_group", "sha256:5e945429851c7ad6143d1dbb66748c9946abd571d82dbcc288ba85e6f4824376",
      ),
    ] {
    let checked : Array[CheckedProgram] = []
    let call = "{\"fn\":\"array_agg\",\"field\":\"id\",\"order_by\":[{\"id\":\"asc\"}],\"max_items\":2}"
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      second_stage=true,
      tea=true,
      second_steps="[{\"row_window\":{\"time\":\"id\",\"kind\":\"fixed\",\"size\":10}},{\"" +
        kind +
        "\":{\"by\":[\"window_start\",\"window_end\",\"id\"],\"aggregates\":{\"a~/b\":" +
        call +
        ",\"value\":" +
        call +
        "}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
    let p = checked[0]
    assert_eq(unit_group_limit_count(p, 1), Some(2))
    let limit = unit_group_limit_at(p, 1, 0).unwrap()
    let source = group_limit_source(limit)
    assert_eq(@relation.aggregate_name(source.call), "a~/b")
    assert_eq(
      group_aggregate_subject(source, 10000),
      "unit:" +
      unit_definition_cid(p, 1).unwrap() +
      "#/steps/1/" +
      kind +
      "/aggregates/a~0~1b/items",
    )
    assert_eq(
      @wire.limit_subject(group_limit_claim(limit)),
      group_aggregate_subject(source, 10000),
    )
    assert_eq(
      @context.group_array_limit_maximum(group_limit_selection(limit)),
      2L,
    )
    let fixed = {
      ..source,
      operation: {
        ..source.operation,
        unit_definition_cid: "sha256:" + "0".repeat(64),
      },
    }
    // Encoder-only namespace; the expected digest is from a separately authored
    // canonical preimage and Node SHA-256, not a compiler-generated expectation.
    assert_eq(
      @wire.cid(
        emit_group_guard_witness(fixed, 2L, {
          work: 100000,
          bytes: 10000,
          nodes: 1000,
          depth: 100,
        }),
      ),
      expected,
    )
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let _ = prepare_program_group_limits(p.units, requirements(p), budget)
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
    let again = prepare_program_group_limits(p.units, requirements(p), exact)
    assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
    assert_eq(
      @wire.limit_cid(group_limit_claim(again[1][0])),
      @wire.limit_cid(group_limit_claim(limit)),
    )
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
      try prepare_program_group_limits(p.units, requirements(p), short) catch {
        _ => ()
      } noraise {
        _ => fail("partial window aggregate limits escaped the budget")
      }
      assert_eq((short.work, short.bytes, short.nodes), before)
    }
  }
}
