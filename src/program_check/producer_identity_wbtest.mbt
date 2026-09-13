///|
test "producer semantics change imports without polluting consumer local contracts" {
  let first_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (before_identity, _, _, _, before) = local_construction_fixture(
    first_budget,
    second_stage=true,
  )
  let next_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (after_identity, _, _, _, after) = local_construction_fixture(
    next_budget,
    second_stage=true,
    producer_expression="id * 2",
  )
  // Same row types and interpreted contract versions, different computation.
  // The consumer sees that change through its producer interface, not by
  // copying the producer body into its own local body or contract closure.
  assert_eq(before.length(), 2)
  assert_eq(after.length(), 2)
  assert_true(
    @context.program_identity_definition_cid(before_identity) !=
    @context.program_identity_definition_cid(after_identity),
  )
  assert_true(
    @context.stage_identity_local_body_cid(before[0].source) !=
    @context.stage_identity_local_body_cid(after[0].source),
  )
  assert_eq(
    @context.stage_identity_local_body_cid(before[1].source),
    @context.stage_identity_local_body_cid(after[1].source),
  )
  for i in 0..<2 {
    assert_eq(before[i].contracts_cid, after[i].contracts_cid)
    assert_true(before[i].definition_cid != after[i].definition_cid)
    assert_eq(before[i].gates, after[i].gates)
  }
  assert_eq(before[1].imports.length(), 2)
  for i in 0..<2 {
    assert_true(before[1].imports[i] != after[1].imports[i])
  }
}

///|
test "invalid consumer operation rejects the entire source construction" {
  let control = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, _, _, valid) = local_construction_fixture(
    control,
    second_stage=true,
    second_steps="[{\"filter\":\"value > 0\"}]",
  )
  assert_eq(valid.length(), 2)
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let initial = (budget.work, budget.bytes, budget.nodes)
  // The first Stage is valid, but the consumer's numeric field cannot serve
  // as a boolean predicate. This is an unused operation relative to Result
  // `from: rows`; liveness must not hide its static failure.
  try
    local_construction_fixture(
      budget,
      second_stage=true,
      second_steps="[{\"filter\":\"value\"}]",
    )
  catch {
    LocalConstructionFailure::Source(_) => ()
    e => raise e
  } noraise {
    _ => fail("invalid consumer exposed a successful construction")
  }
  assert_eq((budget.work, budget.bytes, budget.nodes), initial)
}
