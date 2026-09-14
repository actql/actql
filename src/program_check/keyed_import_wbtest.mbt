///|
test "formal keyed acquisition uses producer-only evidence across Result import" {
  let programs : Array[CheckedProgram] = []
  let _ = remote_construction_fixture(
    { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
    imported_left=true,
    through_check=true,
    checked_results=programs,
  )
  let program = programs[0]
  assert_eq(unit_count(program), 2)
  guard source_execution_at(program, 5).unwrap().kind is KeyedRequest(binding) else {
    fail("missing keyed request")
  }
  assert_eq(binding.stage, 1)
  assert_eq(@sourceviews.keyed_join_step(binding.join), 0)
  let membership = binding.producer
  let (visit, claim, producer) = @capacity.target_membership_coordinates(
    membership,
  )
  assert_true(visit != @capacity.target_membership_consumer_visit(membership))
  assert_eq(claim, 0)
  assert_eq(producer, visit)
  assert_eq(binding.counts.input_rows, 1L)
  let policy = publication_source_policy(
    unit_publication_at(program, 1, 0).unwrap(),
  ).unwrap()
  assert_true(policy.unknown_provenance)
  assert_eq(publication_policy_import_count(policy), 1)
  assert_eq(publication_policy_source_count(policy), 1)
  assert_eq(keyed_input_proof_count(program), 1)
  let retained = keyed_input_proof_at(program, 0).unwrap()
  assert_true(
    physical_equal(
      keyed_input_proof_execution(retained),
      source_execution_at(program, 5).unwrap(),
    ),
  )
  let join_source = keyed_input_proof_source(retained)
  let converted = keyed_input_proof_bound(retained)
  let producer_source = proof_source(converted)
  assert_eq(join_source.source_ordinal, 0)
  assert_eq(producer_source.source_ordinal, 0)
  assert_eq(
    join_source.unit_definition_cid,
    unit_definition_cid(program, 1).unwrap(),
  )
  assert_eq(
    producer_source.unit_definition_cid,
    unit_definition_cid(program, 0).unwrap(),
  )
  assert_true(
    join_source.unit_definition_cid != producer_source.unit_definition_cid,
  )
  let witness = @wire.program_proof_witness(proof_claim(converted))
  let writer = @encode.writer(10000, 1000, 100)
  @wire.emit(witness, writer)
  let text = @encode.finish(writer)
  assert_true(
    text.contains("unit:" + producer_source.unit_definition_cid + "#/steps/0"),
  )
  assert_false(text.contains("unit:" + join_source.unit_definition_cid))
  assert_false(text.contains("checked-step:"))
  for index in [-1, 1, 2147483647] {
    assert_true(keyed_input_proof_at(program, index) is None)
  }
}

///|
test "keyed input proof preparation rejects foreign owners and accounts for conversion" {
  let programs : Array[CheckedProgram] = []
  for _ in 0..<2 {
    let _ = remote_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      imported_left=true,
      through_check=true,
      checked_results=programs,
    )
  }
  let program = programs[0]
  try
    prepare_keyed_input_proofs(
      program.units,
      programs[1].units[0].source_execution,
      { work: 100000, bytes: 100000, nodes: 10000, depth: 100, },
    )
  catch {
    ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("foreign source execution accepted")
  }
  let measured = IdentityBudget::{
    work: 100000,
    bytes: 100000,
    nodes: 10000,
    depth: 100,
  }
  let _ = prepare_keyed_input_proofs(
    program.units,
    program.units[0].source_execution,
    measured,
  )
  let work = 100000 - measured.work
  let bytes = 100000 - measured.bytes
  let nodes = 10000 - measured.nodes
  assert_true(bytes > 0 && nodes > 0)
  let exact = IdentityBudget::{ work, bytes, nodes, depth: 100, }
  let _ = prepare_keyed_input_proofs(
    program.units,
    program.units[0].source_execution,
    exact,
  )
  assert_eq(exact.work, 0)
  assert_eq(exact.bytes, 0)
  assert_eq(exact.nodes, 0)
  for
    (work, bytes, nodes) in [
      (work - 1, bytes, nodes),
      (work, bytes - 1, nodes),
      (work, bytes, nodes - 1),
    ] {
    try
      prepare_keyed_input_proofs(
        program.units,
        program.units[0].source_execution,
        { work, bytes, nodes, depth: 100, },
      )
    catch {
      BudgetExceeded
      | Encoding(@encode.OutputLimit)
      | ProofConversion(@encode.OutputLimit) => ()
      error => raise error
    } noraise {
      _ => fail("partial acquisition proof preparation escaped its budget")
    }
  }
}
