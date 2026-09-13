///|
test "publication row preimage has an independent Host-only vector" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, _, _, units) = local_construction_fixture(budget)
  // Synthetic namespace only for this emitter vector, not an admitted Unit
  // identity. The selected policy/Result still comes from real construction.
  let unit = { ..units[0], definition_cid: "sha256:" + "0".repeat(64), }
  // Fixed independently with Node's canonical serializer and SHA-256, not
  // derived from this builder's output or the row-scope fixture.
  let byte_artifact = prepare_publication_bytes(unit, 0, budget)
  assert_eq(
    @wire.limit_cid(byte_artifact),
    "sha256:e4357512393c07e59a621fc789d223a820f3fdb11de224b41d4cbfec1de9a444",
  )
  assert_eq(
    publication_proof_claims(unit.publications[0].proofs, budget).length(),
    0,
  )
  assert_eq(
    publication_result_subject(unit.definition_cid, "a~/b"),
    "unit:" + unit.definition_cid + "#/results/a~0~1b/rows",
  )
  let ceiling = @context.publication_row_limit_host(unit.publication_rows[0])
  let host = @host.create(ceiling, {
    max_bytes: 10000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  let out = @encode.hashing_writer(10000, 100, 10)
  emit_publication_row_body(unit, 0, host, out, budget)
  // Node crypto over the independently specified preimage, including the
  // fixed all-1000 Host policy. Never copied from emitter output.
  assert_eq(
    @encode.finish_hash(out),
    "c785ac84b1c38e53fb7607dd9eb3ec3781c2662f9e32a4c03c4f9bcfc4eb763e",
  )
  let expected_cid = "sha256:c785ac84b1c38e53fb7607dd9eb3ec3781c2662f9e32a4c03c4f9bcfc4eb763e"
  let artifact_budget = IdentityBudget::{
    work: 1000000,
    bytes: 100000,
    nodes: 10000,
    depth: 100,
  }
  let artifact = prepare_publication_row_artifact(
    unit, 0, host, artifact_budget,
  )
  assert_eq(@wire.limit_cid(artifact), expected_cid)
  let spent = 1000000 - artifact_budget.work
  let short = IdentityBudget::{
    work: spent - 1,
    bytes: 100000,
    nodes: 10000,
    depth: 100,
  }
  try prepare_publication_row_artifact(unit, 0, host, short) catch {
    UnitBuildFailure::BudgetExceeded => ()
    e => raise e
  } noraise {
    _ => fail("publication artifact exceeded work budget")
  }
  assert_eq(short.work, spent - 1)
  assert_eq(short.bytes, 100000)
  assert_eq(short.nodes, 10000)
  let full = @encode.writer(10000, 100, 10)
  emit_publication_row_body(unit, 0, host, full, budget, cid=Some(expected_cid))
  let text = @encode.finish(full)
  let metadata : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 100,
    max_depth: 10,
  }
  let host_writer = @encode.writer(10000, 100, 10)
  @host.emit(host, host_writer)
  let host_wire = @wire.admit(
    @utf8.encode(@encode.finish(host_writer)),
    @host.cid(host),
    metadata,
  ).unwrap()
  let claims = @wire.check_arithmetic_claims([host_wire], {
    max_witnesses: 1,
    max_references: 1,
  }).unwrap()
  let limits : @wire.LimitLimits = {
    max_bytes: 10000,
    max_nodes: 100,
    max_depth: 10,
    max_candidates: 1,
  }
  let admitted = @wire.admit_limit(
    @utf8.encode(text),
    expected_cid,
    claims,
    limits,
  ).unwrap()
  assert_eq(@wire.limit_cid(admitted), expected_cid)
  assert_eq(@wire.limit_enforcement(admitted), EngineAtomic)
  assert_eq(
    @wire.limit_subject(admitted),
    "unit:" + unit.definition_cid + "#/results/out/rows",
  )
  // Reseal a false maximum: integrity alone must not substitute for the
  // existing arithmetic/minimum validator.
  let false_body = text
    .replace(old=",\"resolved_limit_cid\":\"" + expected_cid + "\"", new="")
    .replace(old="\"effective_max\":1000", new="\"effective_max\":1001")
  let false_cid = "sha256:" + @sha.hex(@utf8.encode(false_body))
  let false_full = false_body.replace(
    old="\"subject_ref\":",
    new="\"resolved_limit_cid\":\"" + false_cid + "\",\"subject_ref\":",
  )
  assert_true(
    @wire.admit_limit(@utf8.encode(false_full), false_cid, claims, limits)
    is Err(_),
  )
  let foreign = @host.create(ceiling, {
    max_bytes: 10000,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  // Same ceiling object is accepted; another admission's equal-valued
  // ceiling is not interchangeable with this Result's selected policy owner.
  let other_budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let (_, _, _, _, other) = local_construction_fixture(other_budget)
  let other_host = @host.create(
    @context.publication_row_limit_host(other[0].publication_rows[0]),
    { max_bytes: 10000, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  for (candidate, accept) in [(foreign, true), (other_host, false)] {
    let writer = @encode.hashing_writer(10000, 100, 10)
    try emit_publication_row_body(unit, 0, candidate, writer, budget) catch {
      UnitBuildFailure::ForeignOwner => assert_false(accept)
      e => raise e
    } noraise {
      _ => assert_true(accept)
    }
  }
}

///|
test "publication arithmetic context comes from retained application membership" {
  let budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, units) = remote_construction_fixture(budget)
  let selected = units[0].publication_rows[0]
  let host = @host.create(@context.publication_row_limit_host(selected), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let artifact = prepare_publication_row_artifact(units[0], 0, host, budget)
  assert_eq(
    @wire.limit_subject(artifact),
    publication_result_subject(units[0].definition_cid, "out"),
  )
  assert_true(@context.publication_row_limit_program_count(selected) > 0)
  let execution = units[0].publications[0]
  let wire_writer = @encode.writer(100000, 10000, 100)
  @wire.emit_limit(execution.rows, wire_writer)
  let wire_text = @encode.finish(wire_writer)
  assert_false(wire_text.contains("checked-step:"))
  assert_true(
    wire_text.contains("unit:" + units[0].definition_cid + "#/steps/0"),
  )
  assert_eq(
    publication_proof_count(execution),
    @context.publication_row_limit_program_count(selected),
  )
  let before = budget.work
  let witnesses = publication_proof_claims(execution.proofs, budget)
  let used = before - budget.work
  assert_true(witnesses.length() > 0)
  let claims = @wire.check_arithmetic_claims(witnesses, {
    max_witnesses: witnesses.length(),
    max_references: 10000,
  }).unwrap()
  for i in 0..<@context.publication_row_limit_program_count(selected) {
    let candidate = @context.publication_row_limit_program_at(selected, i).unwrap()
    let original = @wire.program_proof_witness(
      @step_bounds.checked_proof(
        @step_bounds.target_rows_bound(
          @capacity.target_membership_rows(candidate.membership),
        ),
      ),
    )
    let converted = publication_proof_at(execution, i).unwrap()
    let witness = @wire.program_proof_witness(proof_claim(converted))
    let location = proof_source(converted)
    assert_eq(location.unit_definition_cid, units[0].definition_cid)
    assert_true(physical_equal(location.pipeline, units[0].pipeline))
    assert_eq(location.source_ordinal, 0)
    assert_eq(proof_input_count(converted), 0)
    assert_eq(proof_graph_input_count(converted), 0)
    assert_true(proof_input_at(converted, 0) is None)
    assert_true(proof_graph_input_at(converted, -1) is None)
    assert_true(
      physical_equal(
        proof_application(converted),
        @step_bounds.target_rows_bound(
          @capacity.target_membership_rows(candidate.membership),
        ),
      ),
    )
    assert_false(@wire.cid(original) == @wire.cid(witness))
    assert_false(wire_text.contains(@wire.cid(original)))
    assert_true(wire_text.contains(@wire.cid(witness)))
    assert_true(@wire.claim_index(claims, @wire.cid(witness)) is Some(_))
  }
  let exact = IdentityBudget::{ work: used, bytes: 0, nodes: 0, depth: 0, }
  assert_eq(
    publication_proof_claims(execution.proofs, exact).length(),
    witnesses.length(),
  )
  assert_eq(exact.work, 0)
  let short = IdentityBudget::{ work: used - 1, bytes: 0, nodes: 0, depth: 0, }
  try publication_proof_claims(execution.proofs, short) catch {
    UnitBuildFailure::BudgetExceeded => ()
    e => raise e
  } noraise {
    _ => fail("insufficient claim collection work accepted")
  }
}
