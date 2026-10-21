///|
test "Unit construction retains the expression closure of the original operation requirements" {
  for
    expression in [
      "id + 1", "regex_extract('x', '(.)', 1)", "if(FALSE, regex_extract('x', '(.)', 1), 'x')",
    ] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let (identity, requirements, _, _, units) = local_construction_fixture(
      budget,
      second_stage=true,
      producer_expression=expression,
      text_time=true,
      text_policy=true,
    )
    let original = @context.operation_requirements_expressions(
      @context.operation_resolution_requirements(
        @context.operation_closure_index(
          @context.stage_requirement_operations(requirements),
        ),
      ),
    )
    assert_true(
      physical_equal(@context.expression_closure_identity(original), identity),
    )
    if expression != "id + 1" {
      assert_true(@context.expression_closure_count(original) > 0)
    }
    for unit in units {
      assert_true(physical_equal(unit.expressions, original))
      for execution in unit.expression_execution {
        assert_true(physical_equal(execution.owner, original))
      }
    }
  }
}

///|
test "Retained expression closure does not join an equal foreign construction" {
  let (_, requirements, gates, contracts, units) = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    producer_expression="regex_extract('x', '(.)', 1)",
    text_time=true,
    text_policy=true,
  )
  let (_, foreign, _, _, other) = local_construction_fixture(
    { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
    producer_expression="regex_extract('x', '(.)', 1)",
    text_time=true,
    text_policy=true,
  )
  assert_eq(units[0].definition_cid, other[0].definition_cid)
  assert_false(physical_equal(requirements, foreign))
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let before = (budget.work, budget.bytes, budget.nodes)
  try build_units(contracts, foreign, gates, budget) catch {
    UnitBuildFailure::ForeignOwner => ()
    e => raise e
  } noraise {
    _ => fail("equal foreign expression requirements were accepted")
  }
  assert_eq((budget.work, budget.bytes, budget.nodes), before)
}
