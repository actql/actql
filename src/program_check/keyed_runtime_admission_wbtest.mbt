///|
test "unknown keyed estimate retains exact execution obligation without a signed count" {
  let programs : Array[CheckedProgram] = []
  for _ in 0..<2 {
    let _ = remote_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      omit_estimate=true,
    )
  }
  let program = programs[0]
  assert_eq(keyed_input_proof_count(program), 1)
  let obligation = keyed_input_proof_at(program, 0).unwrap()
  let execution = keyed_input_runtime_admission(obligation).unwrap()
  assert_true(keyed_input_proof_bound(obligation) is None)
  assert_true(keyed_input_proof_acquired(obligation) is None)
  assert_true(execution.producer is None)
  assert_true(
    @sourceviews.lookup_requirement_estimate(execution.requirement) is None,
  )
  assert_true(
    @sourceviews.lookup_requirement_admission(execution.requirement)
    is @sourceviews.RuntimeAdmission,
  )
  assert_true(
    physical_equal(
      @sourceviews.lookup_requirement_join(execution.requirement),
      execution.join,
    ),
  )
  assert_eq(@sourceviews.keyed_join_left(execution.join), @pipeline.Step(0))
  assert_eq(keyed_input_proof_source(obligation).source_ordinal, 1)
  assert_true(
    keyed_input_proof_execution(obligation).phase is BeforeProviderAccess,
  )
  assert_true(
    keyed_input_proof_execution(obligation).failure is PreventProviderAccess,
  )
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
    _ => fail("same-wire foreign runtime obligation was accepted")
  }
}
