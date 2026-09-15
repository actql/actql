///|
test "nest resource subjects and guard preimages retain their authored Unit owner" {
  let owners : Array[(NestResourceSource, @context.NestItemLimit)] = []
  for
    (guard_text, expected) in [
      ("", None),
      (",\"max_items\":3", Some(3L)),
      (",\"max_items\":1000", Some(1000L)),
      (",\"max_items\":{\"$param\":\"n\"}", Some(1L)),
      (",\"max_items\":3", Some(3L)),
    ] {
    let checked : Array[CheckedProgram] = []
    let (_, requirements, _, _, units) = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      second_stage=true,
      through_check=true,
      checked_results=checked,
      parameters=true,
      nested_depth=Some(2),
      producer_expression="id",
      producer_suffix=",{\"nest\":{\"with\":\"derived\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\",\"value\"]" +
        guard_text +
        "},\"as\":\"nested\"}",
      producer_result_from="nested",
      extra_step_budget=1,
    )
    let unit = units[0]
    let source = unit_nest_resource_source(unit, unit.pipeline, 1).unwrap()
    let public_source = unit_nest_resource_source_at(checked[0], 0, 1).unwrap()
    assert_true(physical_equal(public_source.nest, source.nest))
    let retained = unit_nest_limit_at(checked[0], 0, 0).unwrap()
    let claim = nest_limits_claim(retained, ChildItems)
    let minimum = @wire.limit_minimum(claim)
    let guards : Array[@wire.WireWitness] = []
    for i in 0..<@derivation.minimum_candidate_count(minimum) {
      let node = @derivation.minimum_candidate_at(minimum, i).unwrap().node
      let candidate = @wire.claim_at(@wire.limit_claims(claim), node).unwrap()
      if @wire.source(candidate) is AuthorGuard(_, _) {
        guards.push(candidate)
      }
    }
    assert_eq(guards.length(), if expected is None { 0 } else { 1 })
    let public_guard = guards.get(0)
    assert_eq(public_guard.map(w => @wire.value(w)), expected)
    assert_true(unit_nest_resource_source(unit, units[1].pipeline, 1) is None)
    for invalid in [-1, 0, 2, 2147483647] {
      assert_true(
        unit_nest_resource_source(unit, unit.pipeline, invalid) is None,
      )
    }
    let work = unit.definition_cid.length() + 64
    for
      (scope, suffix) in [
        (ChildItems, "child-arrays/items"),
        (EmptyItems, "empty-array/items"),
        (GroupedBytes, "child-arrays/bytes"),
        (AttachedBytes, "attachment/bytes"),
      ] {
      assert_eq(
        nest_resource_subject(source, scope, work),
        "unit:" + unit.definition_cid + "#/steps/1/nest/" + suffix,
      )
      try nest_resource_subject(source, scope, work - 1) catch {
        BudgetExceeded => ()
        error => raise error
      } noraise {
        _ => fail("unbudgeted nest subject")
      }
    }
    let closure = @context.stage_requirement_operations(requirements)
    let mut visits = 0
    for i in 0..<@context.operation_closure_count(closure) {
      guard @context.operation_closure_at(closure, i)
        is Some(ExecutionCheck(NestItems(selected))) else {
        continue
      }
      let budget = IdentityBudget::{
        work: 1000000,
        bytes: 100000,
        nodes: 10000,
        depth: 100,
      }
      let before = IdentityBudget::{ ..budget, }
      assert_true(
        physical_equal(selected.operation, source.nest),
        msg="nest owner",
      )
      assert_true(
        physical_equal(selected.site.pipeline, source.operation.pipeline),
        msg="pipeline owner",
      )
      assert_eq(selected.site.step, source.operation.source_ordinal)
      assert_true(
        physical_equal(
          @context.expression_closure_identity(
            @context.operation_requirements_expressions(
              @context.operation_resolution_requirements(selected.owner),
            ),
          ),
          source.owner,
        ),
        msg="source owner",
      )
      let witness = emit_nest_guard_witness(source, selected, budget)
      match (expected, witness) {
        (None, None) => ()
        (Some(value), Some(witness)) => {
          assert_eq(@wire.value(witness), value)
          assert_eq(@wire.dependencies(witness), [unit.definition_cid])
          assert_true(
            @wire.source(witness) is AuthorGuard(path, definition) &&
            path == "$.steps[1].nest.max_items" &&
            definition == unit.definition_cid,
          )
          // Independent canonical source-witness preimage, not the product emitter.
          let body = "{\"dependencies\":[\"" +
            unit.definition_cid +
            "\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.guard.nested-array-items\",\"role\":\"author_guard\",\"source\":{\"kind\":\"author_guard\",\"program_definition_cid\":\"" +
            unit.definition_cid +
            "\",\"source_path\":\"$.steps[1].nest.max_items\"},\"unit\":\"array_items\",\"value\":" +
            value.to_string() +
            ",\"version\":\"actql-bound-witness/0.1\"}"
          assert_eq(
            @wire.cid(witness),
            "sha256:" + @sha.text_hex(body).unwrap(),
          )
        }
        _ => fail("nest guard absence or binding changed")
      }
      let used = (
        before.work - budget.work,
        before.bytes - budget.bytes,
        before.nodes - budget.nodes,
      )
      let exact = IdentityBudget::{
        work: used.0,
        bytes: used.1,
        nodes: used.2,
        depth: 100,
      }
      let _ = emit_nest_guard_witness(source, selected, exact)
      assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
      let short = IdentityBudget::{ ..before, work: used.0 - 1, }
      try emit_nest_guard_witness(source, selected, short) catch {
        BudgetExceeded | Encoding(_) => ()
        error => raise error
      } noraise {
        _ => fail("unbudgeted nest guard")
      }
      assert_eq(
        (short.work, short.bytes, short.nodes),
        (used.0 - 1, before.bytes, before.nodes),
      )
      if visits == 0 {
        owners.push((source, selected))
      }
      visits += 1
    }
    assert_eq(visits, 3)
  }
  assert_eq(
    owners[1].0.operation.unit_definition_cid,
    owners[4].0.operation.unit_definition_cid,
  )
  assert_false(physical_equal(owners[1].0.nest, owners[4].0.nest))
  let budget = IdentityBudget::{
    work: 1000000,
    bytes: 100000,
    nodes: 10000,
    depth: 100,
  }
  try emit_nest_guard_witness(owners[1].0, owners[4].1, budget) catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("equal identity substituted a foreign nest owner")
  }
  assert_eq(budget.work, 1000000)
}
