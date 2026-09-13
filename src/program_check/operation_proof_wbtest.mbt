///|
test "proof graph conversion rejects a foreign Unit without spending caller budget" {
  let budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = remote_construction_fixture(budget)
  let candidate = @context.publication_row_limit_program_at(
    units[0].publication_rows[0],
    0,
  ).unwrap()
  let bound = @step_bounds.target_rows_bound(
    @capacity.target_membership_rows(candidate.membership),
  )
  let (_, _, _, _, other) = remote_construction_fixture(budget)
  assert_eq(units[0].definition_cid, other[0].definition_cid)
  let before = IdentityBudget::{ ..budget, }
  try reidentify_step_graph(other, bound, budget) catch {
    UnitBuildFailure::ForeignOwner => ()
    e => raise e
  } noraise {
    _ => fail("foreign graph owner accepted")
  }
  assert_eq(budget.work, before.work)
  assert_eq(budget.bytes, before.bytes)
  assert_eq(budget.nodes, before.nodes)
}

///|
test "reidentified minimum operands are canonical after CID replacement" {
  let a = "sha256:" + "1".repeat(64)
  let b = "sha256:" + "2".repeat(64)
  let c = "sha256:" + "3".repeat(64)
  let budget = IdentityBudget::{
    work: 100000,
    bytes: 10000,
    nodes: 1000,
    depth: 20,
  }
  // The original canonical order is reversed by replacement. Two distinct
  // original witnesses can also converge to the same persistent witness.
  let mapping : Map[String, String] = Map([(a, c), (b, a), (c, a)])
  let writer = @encode.writer(10000, 1000, 20)
  emit_reidentified_derivation(Minimum([a, b, c]), mapping, writer, budget)
  assert_eq(
    @encode.finish(writer),
    "{\"inputs\":[\"\{a}\",\"\{c}\"],\"op\":\"min\"}",
  )
}

///|
test "Unit output proof uses independently fixed source preimage" {
  let budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = remote_construction_fixture(budget)
  let candidate = @context.publication_row_limit_program_at(
    units[0].publication_rows[0],
    0,
  ).unwrap()
  let bound = @step_bounds.target_rows_bound(
    @capacity.target_membership_rows(candidate.membership),
  )
  let synthetic = { ..units[0], definition_cid: "sha256:" + "0".repeat(64), }
  let location = unit_operation_source(
    synthetic,
    @step_bounds.checked_pipeline(bound),
    @step_bounds.checked_step(bound),
  ).unwrap()
  assert_eq(location.source_ordinal, 0)
  let graph = reidentify_step_graph([synthetic], bound, budget)
  assert_eq(
    @wire.cid(@wire.program_proof_witness(graph.proof)),
    "sha256:8aa21a53557ce5864441724f2088a6757e8883e5a2fac0d9cb23a340a5088720",
  )
  let before = IdentityBudget::{ ..budget, }
  let rebuilt = reidentify_step(synthetic, bound, [], budget)
  let exact = IdentityBudget::{ ..before, work: before.work - budget.work, }
  let exact_result = reidentify_step(synthetic, bound, [], exact)
  assert_eq(exact.work, 0)
  assert_eq(
    @wire.cid(@wire.program_proof_witness(exact_result.proof)),
    @wire.cid(@wire.program_proof_witness(rebuilt.proof)),
  )
  let short = IdentityBudget::{ ..before, work: before.work - budget.work - 1, }
  let short_before = IdentityBudget::{ ..short, }
  try reidentify_step(synthetic, bound, [], short) catch {
    UnitBuildFailure::BudgetExceeded => ()
    e => raise e
  } noraise {
    _ => fail("insufficient conversion work accepted")
  }
  assert_eq(short.work, short_before.work)
  assert_eq(short.bytes, short_before.bytes)
  assert_eq(short.nodes, short_before.nodes)
  assert_true(physical_equal(rebuilt.original, bound))
  assert_eq(rebuilt.inputs.length(), 0)
  assert_eq(rebuilt.location.unit_definition_cid, synthetic.definition_cid)
  let rebuilt_witness = @wire.program_proof_witness(rebuilt.proof)
  assert_eq(
    @wire.cid(rebuilt_witness),
    "sha256:8aa21a53557ce5864441724f2088a6757e8883e5a2fac0d9cb23a340a5088720",
  )
  assert_true(@wire.program_proof_form(rebuilt.proof) is DerivedInputs)
  let arithmetic = @wire.check_arithmetic_claims([rebuilt_witness], {
    max_witnesses: 1,
    max_references: 1,
  }).unwrap()
  assert_eq(@wire.claim_count(arithmetic), 1)
  let writer = identity_writer(budget)
  emit_unit_output_proof(location, bound, [], writer, budget)
  assert_eq(
    identity_finish(budget, writer),
    "sha256:dd40942a43692c6f7eee9c68d18fbb6eafd73bca1d5c1564ea4df9909d03ccd3",
  )
  let actual = unit_operation_source(units[0], units[0].pipeline, 0).unwrap()
  let actual_writer = identity_writer(budget)
  emit_unit_output_proof(actual, bound, [], actual_writer, budget)
  assert_false(
    identity_finish(budget, actual_writer) ==
    "sha256:dd40942a43692c6f7eee9c68d18fbb6eafd73bca1d5c1564ea4df9909d03ccd3",
  )
  let other_budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, other) = remote_construction_fixture(other_budget)
  let foreign = unit_operation_source(other[0], other[0].pipeline, 0).unwrap()
  let out = identity_writer(budget)
  try emit_unit_output_proof(foreign, bound, [], out, budget) catch {
    UnitBuildFailure::ForeignOwner => ()
    e => raise e
  } noraise {
    _ => fail("foreign operation proof owner accepted")
  }
}
