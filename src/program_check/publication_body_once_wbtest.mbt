///|
test "one publication artifact prepares its original row candidates once" {
  let construction = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = remote_construction_fixture(construction)
  let unit = units[0]
  let selected = unit.publication_rows[0]
  assert_true(@context.publication_row_limit_program_count(selected) > 0)
  let host = @host.create(@context.publication_row_limit_host(selected), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let budget = IdentityBudget::{
    work: 1000000,
    bytes: 100000,
    nodes: 10000,
    depth: 100,
  }
  let preparations = [0]
  let artifact = prepare_publication_row_artifact(
    unit,
    0,
    host,
    budget,
    on_body_preparation=Some(() => preparations[0] += 1),
  )
  assert_eq(preparations[0], 1)
  assert_eq(@wire.limit_enforcement(artifact), EngineAtomic)
  assert_eq(
    @wire.limit_subject(artifact),
    publication_result_subject(unit.definition_cid, "out"),
  )
}

///|
test "publication body reuse does not accept an equal foreign Host owner" {
  let construction = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, _, _, original) = local_construction_fixture(construction)
  let other_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, _, _, foreign) = local_construction_fixture(other_budget)
  let host = @host.create(
    @context.publication_row_limit_host(foreign[0].publication_rows[0]),
    { max_bytes: 10000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let expected = @host.create(
    @context.publication_row_limit_host(original[0].publication_rows[0]),
    { max_bytes: 10000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  assert_eq(@host.cid(host), @host.cid(expected))
  let budget = IdentityBudget::{
    work: 1000000,
    bytes: 100000,
    nodes: 10000,
    depth: 100,
  }
  let preparations = [0]
  try
    prepare_publication_row_artifact(
      original[0],
      0,
      host,
      budget,
      on_body_preparation=Some(() => preparations[0] += 1),
    )
  catch {
    UnitBuildFailure::ForeignOwner => ()
    e => raise e
  } noraise {
    _ => fail("foreign original publication Host was accepted")
  }
  assert_eq(preparations[0], 0)
  assert_eq(budget.work, 1000000)
  assert_eq(budget.bytes, 100000)
  assert_eq(budget.nodes, 10000)
}
