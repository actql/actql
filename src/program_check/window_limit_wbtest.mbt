///|
test "formal window limits retain input proofs and producer Unit identity across imports" {
  for (kind, factor) in [("fixed", 1L), ("sliding", 4L)] {
    let checked : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=checked,
      second_stage=true,
      tea=true,
      generated_rows=Some("[{\"id\":1}]"),
      generated_proofs=[keyed_sourceview_claim()],
      generated_proof_stage=0,
      producer_suffix=",{\"row_window\":{\"time\":\"id\",\"kind\":\"" +
        kind +
        "\",\"size\":10,\"step\":3},\"as\":\"windowed\"}",
      producer_result_from="windowed",
      extra_step_budget=2,
    )
    let p = checked[0]
    assert_eq(unit_window_limit_count(p, 0), Some(1))
    assert_eq(unit_window_limit_count(p, 1), Some(0))
    assert_true(unit_window_limit_at(p, 0, -1) is None)
    assert_true(unit_window_limit_at(p, 0, 1) is None)
    let limit = unit_window_limit_at(p, 0, 0).unwrap()
    assert_true(physical_equal(limit, unit_window_limit_at(p, 0, 0).unwrap()))
    assert_eq(window_limit_selection(limit).maximum, factor)
    assert_true(window_limit_proof_count(limit) > 0)
    assert_true(window_limit_proof_at(limit, -1) is None)
    assert_true(
      window_limit_proof_at(limit, window_limit_proof_count(limit)) is None,
    )
    for candidate in [-1, window_limit_proof_count(limit)] {
      try
        window_input_proof(
          p.units,
          window_limit_source(limit),
          window_limit_selection(limit),
          candidate,
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        )
      catch {
        UnitBuildFailure::ForeignOwner => ()
        error => raise error
      } noraise {
        _ => fail("invalid window input candidate accepted")
      }
    }
    let output = @encode.writer(100000, 10000, 100)
    @wire.emit_limit(window_limit_claim(limit), output)
    let text = @encode.finish(output)
    assert_false(text.contains("checked-step:"))
    assert_true(text.contains("\"author_guard_binding\":\"absent\""))
    assert_true(text.contains("\"enforcement\":\"engine_atomic\""))
    assert_true(text.contains("\"unit\":\"rows\""))
    assert_true(text.contains("\"role\":\"host_ceiling\""))
    assert_true(text.contains("\"role\":\"proven_upper_bound\""))
    assert_eq(
      @wire.limit_subject(window_limit_claim(limit)),
      "unit:" + unit_definition_cid(p, 0).unwrap() + "#/steps/2",
    )
    for i in 0..<window_limit_proof_count(limit) {
      let proof = window_limit_proof_at(limit, i).unwrap()
      assert_eq(
        @wire.value(
          @wire.program_proof_witness(window_input_proof_claim(proof)),
        ),
        factor,
      )
      assert_eq(
        window_input_proof_source(proof).unit_definition_cid,
        unit_definition_cid(p, 0).unwrap(),
      )
      let rebuilt = window_input_proof(
        p.units,
        window_limit_source(limit),
        window_limit_selection(limit),
        i,
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      )
      assert_eq(
        @wire.cid(
          @wire.program_proof_witness(window_input_proof_claim(rebuilt)),
        ),
        @wire.cid(@wire.program_proof_witness(window_input_proof_claim(proof))),
      )
    }
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let built = prepare_program_window_limits(p.units, requirements(p), budget)
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
    let repeated = prepare_program_window_limits(
      p.units,
      requirements(p),
      exact,
    )
    assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
    assert_eq(
      @wire.limit_cid(window_limit_claim(built[0][0])),
      @wire.limit_cid(window_limit_claim(repeated[0][0])),
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
      try prepare_program_window_limits(p.units, requirements(p), short) catch {
        _ => ()
      } noraise {
        _ => fail("partial window limit assembly escaped its shared budget")
      }
      assert_eq((short.work, short.bytes, short.nodes), before)
    }
  }
}
