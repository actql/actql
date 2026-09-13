///|
test "group guard witnesses retain bound values and omit absent guards" {
  for
    (guard_text, expected) in [
      ("", None),
      (",\"max_items\":2", Some(2L)),
      (",\"max_items\":1000", Some(1000L)),
      (",\"max_items\":{\"$param\":\"n\"}", Some(1L)),
    ] {
    let programs : Array[CheckedProgram] = []
    let call = "{\"fn\":\"array_agg\",\"field\":\"value\",\"order_by\":[{\"id\":\"asc\"}]" +
      guard_text +
      "}"
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      parameters=true,
      second_stage=true,
      through_check=true,
      checked_results=programs,
      second_steps="[{\"group\":{\"by\":[\"id\"],\"aggregates\":{\"items\":" +
        call +
        ",\"value\":" +
        call +
        "}},\"as\":\"selected\"}]",
      second_result_from="selected",
      extra_step_budget=2,
    )
    let program = programs[0]
    let limit = unit_group_array_limit(
      program,
      1,
      0,
      0,
      max_work=10000000,
      max_bytes=1000000,
      max_nodes=100000,
      max_depth=100,
    )
    assert_eq(group_limit_proof_count(limit), 0)
    let out = @encode.writer(100000, 10000, 100)
    @wire.emit_limit(group_limit_claim(limit), out)
    let text = @encode.finish(out)
    assert_true(
      text.contains(
        "\"effective_max\":" + expected.unwrap_or(1000L).to_string(),
      ),
    )
    assert_true(
      text.contains(
        "\"author_guard_binding\":\"" +
        (if expected is None {
          "absent"
        } else if expected == Some(1000L) {
          "currently_non_binding"
        } else {
          "binding"
        }) +
        "\"",
      ),
    )
    assert_true(text.contains("\"enforcement\":\"engine_atomic\""))
    assert_eq(
      @wire.limit_subject(group_limit_claim(limit)),
      group_aggregate_subject(group_limit_source(limit), 10000),
    )
    let witness = unit_group_guard_witness(
      program,
      1,
      0,
      0,
      max_work=1000000,
      max_bytes=1000000,
      max_nodes=10000,
      max_depth=100,
    )
    match (expected, witness) {
      (None, None) => ()
      (Some(value), Some(witness)) => {
        assert_eq(@wire.value(witness), value)
        assert_true(
          @wire.source(witness) is AuthorGuard(path, definition) &&
          definition == program.units[1].definition_cid &&
          path == "$.steps[0].group.aggregates[\"items\"].max_items",
        )
        let source = unit_group_aggregate_source_at(program, 1, 0, 0).unwrap()
        let budget = IdentityBudget::{
          work: 1000000,
          bytes: 1000000,
          nodes: 10000,
          depth: 100,
        }
        let before = IdentityBudget::{ ..budget, }
        let direct = emit_group_guard_witness(source, value, budget)
        assert_eq(@wire.cid(direct), @wire.cid(witness))
        let used = before.work - budget.work
        let exact = IdentityBudget::{ ..before, work: used, }
        assert_eq(
          @wire.cid(emit_group_guard_witness(source, value, exact)),
          @wire.cid(witness),
        )
        assert_eq(exact.work, 0)
        let short = IdentityBudget::{ ..before, work: used - 1, }
        try emit_group_guard_witness(source, value, short) catch {
          BudgetExceeded => ()
          Encoding(_) => ()
          error => raise error
        } noraise {
          _ => fail("short guard preparation budget accepted")
        }
        assert_eq(short.work, used - 1)
        assert_eq(short.bytes, before.bytes)
        if value == 2L {
          // Fixed synthetic namespace and preimage from the independent corpus.
          let fixed = {
            ..source,
            operation: {
              ..source.operation,
              unit_definition_cid: "sha256:" + "0".repeat(64),
            },
          }
          assert_eq(
            @wire.cid(emit_group_guard_witness(fixed, value, before)),
            "sha256:ca0dad20b0eff03aa05a4b7a4817f29820ffe63bd06ff0305849efa1997b59b7",
          )
        }
      }
      _ => fail("authored guard presence changed")
    }
  }
}
