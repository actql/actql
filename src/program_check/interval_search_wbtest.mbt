///|
test "interval search emitter matches independent witness-based preimage" {
  let subject = "unit:sha256:" + "0".repeat(64) + "#/steps/0"
  let left = [
    "sha256:d9b8354c7814eddf8fd6b22e899d9100e38506abbabe65eed6f5110d5f9fd82e",
  ]
  let right = [
    "sha256:d6b1ed513de2d9d8bb98243938ce2972591bc2147057c38abd6e3c4a28f1497b",
  ]
  let text = @encode.writer(10000, 100, 10)
  emit_interval_search_body(subject, 6, left, right, text)
  let canonical = @encode.finish(text)
  let hash = @encode.hashing_writer(10000, 100, 10)
  emit_interval_search_body(subject, 6, left, right, hash)
  assert_eq(
    @encode.finish_hash(hash),
    "b90a72a2ae077855a59b15dfda98bd74d9f2b86295f3837cf58aee2a3bad406d",
  )
  assert_eq(
    @sha.hex(@utf8.encode(canonical)),
    "b90a72a2ae077855a59b15dfda98bd74d9f2b86295f3837cf58aee2a3bad406d",
  )
}

///|
fn formal_interval_steps(kind : String) -> String {
  "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"value\":2}]},\"as\":\"seed\"},{\"interval_join\":{\"with\":\"seed\",\"kind\":\"" +
  kind +
  "\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"value\"}" +
  ",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}" +
  "},\"as\":\"selected\"}]"
}

///|
test "formal interval Program retains Unit search limits and original proof graphs" {
  for kind in ["inner", "left", "semi", "anti"] {
    let results : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=results,
      second_stage=true,
      tea=true,
      second_steps=formal_interval_steps(kind),
      second_result_from="selected",
      second_join_capacity=true,
      second_join_step=1,
      generated_proofs=[keyed_sourceview_claim()],
      extra_step_budget=2,
    )
    let p = results[0]
    assert_eq(unit_interval_search_limit_count(p, 0), Some(0))
    assert_eq(unit_interval_search_limit_count(p, 1), Some(1))
    let limit = unit_interval_search_limit_at(p, 1, 0).unwrap()
    let writer = @encode.writer(100000, 10000, 100)
    emit_interval_search_limit(limit, writer)
    let text = @encode.finish(writer)
    assert_false(text.contains("checked-step:"))
    assert_true(
      text.contains("unit:" + unit_definition_cid(p, 1).unwrap() + "#/steps/1"),
    )
    assert_true(text.contains("\"unit\":\"pair_visits\""))
    assert_true(text.contains("\"maximum\":1"))
    assert_eq(
      interval_search_limit_cid(limit),
      "sha256:" + @sha.hex(@utf8.encode(text)),
    )
    for side in 0..<2 {
      assert_eq(interval_search_limit_proof_count(limit, side), 1)
      let proof = interval_search_limit_proof_at(limit, side, 0).unwrap()
      assert_eq(
        proof_source(proof).unit_definition_cid,
        unit_definition_cid(p, 1).unwrap(),
      )
      assert_eq(proof_source(proof).source_ordinal, 0)
      let witness = @wire.program_proof_witness(proof_claim(proof))
      assert_true(text.contains(@wire.cid(witness)))
      assert_true(
        physical_equal(
          proof_application(proof),
          @step_bounds.target_rows_bound(
            @capacity.target_membership_rows(
              @context.interval_search_bound_candidate_at(
                interval_search_limit_selection(limit).bounds,
                side,
                0,
              ).unwrap(),
            ),
          ),
        ),
      )
    }
    assert_true(unit_interval_search_limit_at(p, 1, 1) is None)
    for
      foreign_units in [
        [p.units[1], p.units[0]],
        [p.units[0]],
        [p.units[0], p.units[1], p.units[1]],
      ] {
      let foreign_budget = IdentityBudget::{
        work: 10000000,
        bytes: 1000000,
        nodes: 100000,
        depth: 100,
      }
      let rejected = try {
        ignore(
          prepare_program_interval_search_limits(
            foreign_units,
            requirements(p),
            foreign_budget,
          ),
        )
        false
      } catch {
        UnitBuildFailure::ForeignOwner => true
        _ => false
      }
      assert_true(rejected)
      assert_eq(
        (foreign_budget.work, foreign_budget.bytes, foreign_budget.nodes),
        (10000000, 1000000, 100000),
      )
    }
    let duplicate_budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let duplicate = try {
      ignore(
        assemble_interval_search_limit(
          [p.units[0], p.units[1], p.units[1]],
          limit.source,
          limit.selected,
          duplicate_budget,
        ),
      )
      false
    } catch {
      UnitBuildFailure::ForeignOwner => true
      _ => false
    }
    assert_true(duplicate)
    assert_eq(duplicate_budget.work, 10000000)
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let rebuilt = prepare_program_interval_search_limits(
      p.units,
      requirements(p),
      budget,
    )
    assert_eq(
      interval_search_limit_cid(rebuilt[1][0]),
      interval_search_limit_cid(limit),
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
    ignore(
      prepare_program_interval_search_limits(p.units, requirements(p), exact),
    )
    assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
    for axis in 0..<3 {
      let short = IdentityBudget::{
        work: used.0 - (if axis == 0 { 1 } else { 0 }),
        bytes: used.1 - (if axis == 1 { 1 } else { 0 }),
        nodes: used.2 - (if axis == 2 { 1 } else { 0 }),
        depth: 100,
      }
      let before = (short.work, short.bytes, short.nodes)
      let failed = try {
        ignore(
          prepare_program_interval_search_limits(
            p.units,
            requirements(p),
            short,
          ),
        )
        false
      } catch {
        _ => true
      }
      assert_true(failed)
      assert_eq((short.work, short.bytes, short.nodes), before)
    }
  }
}

///|
test "formal interval refuses missing search proof without returning partial Program" {
  let results : Array[CheckedProgram] = []
  let rejected = try {
    ignore(
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=results,
        second_stage=true,
        tea=true,
        second_steps=formal_interval_steps("semi"),
        second_result_from="selected",
        second_join_capacity=true,
        second_join_step=1,
        extra_step_budget=2,
      ),
    )
    false
  } catch {
    LocalConstructionFailure::Closure(
      ConstructionFailure::IntervalSearch(MissingSearchBound(_))
    ) => true
    _ => false
  }
  assert_true(rejected)
  assert_eq(results.length(), 0)
}

///|
test "imported interval search retains producer Unit proofs without consumer copies" {
  for kind in ["inner", "left", "semi", "anti"] {
    let output : Array[CheckedProgram] = []
    let steps = "[{\"interval_join\":{\"with\":\"again\",\"kind\":\"" +
      kind +
      "\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"value\"},\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}},\"as\":\"selected\"}]"
    ignore(
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=output,
        second_stage=true,
        tea=true,
        generated_rows=Some("[{\"id\":1}]"),
        generated_proofs=[keyed_sourceview_claim()],
        generated_proof_stage=0,
        second_steps=steps,
        second_result_from="selected",
        second_join_capacity=true,
        second_join_step=0,
        extra_step_budget=1,
      ),
    )
    let p = output[0]
    let limit = unit_interval_search_limit_at(p, 1, 0).unwrap()
    assert_eq(
      limit.source.unit_definition_cid,
      unit_definition_cid(p, 1).unwrap(),
    )
    assert_eq(@step_bounds.interval_search_upper(limit.selected.product), 1L)
    let writer = @encode.writer(100000, 10000, 100)
    emit_interval_search_limit(limit, writer)
    let text = @encode.finish(writer)
    assert_false(text.contains("checked-step:"))
    for side in 0..<2 {
      assert_eq(interval_search_limit_proof_count(limit, side), 2)
      for index in 0..<2 {
        let proof = interval_search_limit_proof_at(limit, side, index).unwrap()
        assert_eq(
          proof_source(proof).unit_definition_cid,
          unit_definition_cid(p, 0).unwrap(),
        )
        assert_eq(proof_source(proof).source_ordinal, 0)
        assert_true(
          text.contains(
            @wire.cid(@wire.program_proof_witness(proof_claim(proof))),
          ),
        )
        let membership = @context.interval_search_bound_candidate_at(
          limit.selected.bounds,
          side,
          index,
        ).unwrap()
        assert_eq(@capacity.target_membership_consumer_visit(membership), 0)
        assert_eq(
          @capacity.target_membership_coordinates(membership),
          (index + 1, 0, index + 1),
        )
      }
    }
    assert_eq(limit.left_refs.length(), 1)
    assert_eq(limit.right_refs.length(), 1)
    assert_eq(limit.left_refs, limit.right_refs)
    let owner = @context.interval_search_bound_owner(limit.selected.bounds)
    let requirement = @context.interval_search_bound_requirement(
      limit.selected.bounds,
    )
    let work = @context.interval_search_bound_work(limit.selected.bounds)
    assert_true(
      @context.collect_interval_search_bounds(owner, requirement, work, 4)
      is Ok(_),
    )
    assert_true(
      @context.collect_interval_search_bounds(owner, requirement, work - 1, 4)
      is Err(@context.BudgetExceeded),
    )
    assert_true(
      @context.collect_interval_search_bounds(owner, requirement, work, 3)
      is Err(@context.BudgetExceeded),
    )
  }
}
