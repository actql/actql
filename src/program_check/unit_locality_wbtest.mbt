///|
test "an additional Stage changes Program identity but not predecessor Units" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (original, _, _, _, before) = local_construction_fixture(
    budget,
    second_stage=true,
  )
  let extended_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (extended, _, _, _, after) = local_construction_fixture(
    extended_budget,
    unrelated_stage=true,
  )
  assert_eq(before.length(), 2)
  assert_eq(after.length(), 3)
  assert_true(
    @context.program_identity_definition_cid(original) !=
    @context.program_identity_definition_cid(extended),
  )
  for i in 0..<2 {
    assert_eq(before[i].definition_cid, after[i].definition_cid)
    assert_eq(before[i].contracts_cid, after[i].contracts_cid)
    assert_eq(before[i].contracts, after[i].contracts)
    assert_eq(before[i].imports, after[i].imports)
    assert_eq(before[i].gates, after[i].gates)
    assert_false(physical_equal(before[i].source, after[i].source))
  }
  // The added Stage is still checked and receives its own local schema and
  // predecessor-success requirement even though no root Result exports it.
  assert_true(after[2].contracts_cid != after[1].contracts_cid)
  assert_eq(after[2].interfaces.length(), 0)
  assert_eq(after[2].gates.length(), 1)
}
