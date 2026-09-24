///|
test "publication execution retains target dependencies and rejects another Program" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, _, _, units) = local_construction_fixture(
    budget,
    second_stage=true,
  )
  for stage in 0..<2 {
    let check = units[stage].publications[0]
    let result = @context.publication_row_limit_result(check.selection)
    assert_eq(result.stage, stage)
    assert_eq(result.result_index, 0)
    assert_eq(publication_result_name(check), "out")
    assert_true(check.phase is BeforeResultPublication)
    assert_true(check.failure is PreventResultPublication)
    assert_true(
      physical_equal(check.selection, units[stage].publication_rows[0]),
    )
    assert_true(
      physical_equal(
        @publication.port_orders(result.port),
        @context.checked_orders(result.context),
      ),
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
  )
  // Equal identities and equal numeric limits are not process-local ownership.
  assert_eq(units[0].definition_cid, other[0].definition_cid)
  let forged = { ..units[0], publication_rows: other[0].publication_rows, }
  let work = budget.work
  try prepare_publication_execution(forged, 0, budget) catch {
    UnitBuildFailure::ForeignOwner => ()
    e => raise e
  } noraise {
    _ => fail("foreign publication selection accepted")
  }
  assert_eq(budget.work, work)
  let wrong_stage = { ..units[0], publication_rows: units[1].publication_rows, }
  try prepare_publication_execution(wrong_stage, 0, budget) catch {
    UnitBuildFailure::ForeignOwner => ()
    e => raise e
  } noraise {
    _ => fail("another Stage's publication selection accepted")
  }
  assert_eq(budget.work, work)
}
