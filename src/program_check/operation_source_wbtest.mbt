///|
test "Unit operation locations use owned source slots rather than producer visit indices" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, _, _, units) = local_construction_fixture(
    budget,
    second_stage=true,
    second_steps="[{\"derive\":{\"extra\":\"id + 2\"}}]",
  )
  for stage in 0..<2 {
    let unit = units[stage]
    let location = unit_operation_source(unit, unit.pipeline, 0).unwrap()
    assert_eq(location.unit_definition_cid, unit.definition_cid)
    assert_true(physical_equal(location.stage, unit.source))
    assert_true(physical_equal(location.pipeline, unit.pipeline))
    assert_eq(location.source_ordinal, 0)
    assert_eq(
      unit_operation_subject(location, budget),
      "unit:" + unit.definition_cid + "#/steps/0",
    )
    let raw = @decode.element_at(@pipeline.source(unit.pipeline), 0).unwrap()
    assert_eq(
      @decode.tree_index(raw, location.source),
      @decode.tree_index(raw, raw),
    )
    assert_true(@decode.tree_index(raw, location.source) is Some(_))
    assert_true(unit_operation_source(unit, unit.pipeline, -1) is None)
    assert_true(unit_operation_source(unit, unit.pipeline, 1) is None)
    // The imported producer also uses index zero. It is not a local operation.
    assert_true(
      unit_operation_source(unit, units[1 - stage].pipeline, 0) is None,
    )
  }
  let other_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, _, _, other) = local_construction_fixture(
    other_budget,
    second_stage=true,
    second_steps="[{\"derive\":{\"extra\":\"id + 2\"}}]",
  )
  assert_eq(units[0].definition_cid, other[0].definition_cid)
  assert_true(unit_operation_source(units[0], other[0].pipeline, 0) is None)
}
