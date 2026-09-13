///|
test "formal Sequence output evidence reaches Result publication through source-owned preparation" {
  for empty in [false, true] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      parameters=true,
      tea=true,
      second_sequence_capacity=true,
      sequence_output_proof=true,
      generated_rows=if empty { Some("[]") } else { None },
      second_steps=sequence_test_steps(false, "allow", "adjacent", ""),
      second_result_from="selected",
      extra_step_budget=2,
    )
    assert_eq(programs.length(), 1)
    let program = programs[0]
    let publication = unit_publication_at(program, 1, 0).unwrap()
    assert_eq(publication_proof_count(publication), 1)
    let proof = publication_proof_at(publication, 0).unwrap()
    assert_true(
      @step_bounds.checked_enforcement(proof_application(proof))
      is Some(SequenceEnforcement(_)),
    )
    assert_eq(proof_external_input_count(proof), 1)
    let external = proof_external_input_at(proof, 0).unwrap()
    assert_eq(
      @wire.program_proof_input_at(proof_claim(proof), 0),
      Some(@wire.cid(external)),
    )
    guard @wire.source(@wire.program_proof_witness(proof_claim(proof)))
      is @wire.Program(subject, _) else {
      fail("missing Unit proof")
    }
    assert_eq(
      subject,
      "unit:" + unit_definition_cid(program, 1).unwrap() + "#/steps/0",
    )
  }
}

///|
test "formal preparation cannot replace authored Sequence proof candidates with Host ceilings" {
  let programs : Array[CheckedProgram] = []
  try
    local_construction_fixture(
      { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      parameters=true,
      tea=true,
      second_sequence_capacity=true,
      sequence_output_proof=true,
      second_steps=sequence_test_steps(
        false, "allow", "adjacent", ",\"max_output_rows\":1",
      ),
      second_result_from="selected",
      extra_step_budget=2,
    )
  catch {
    LocalConstructionFailure::Source(
      SourceFailure::SourceView(
        Context(Stages(Capacity(1, 0, Program(InvalidSequenceProof(_)))))
      )
    ) => ()
    e => raise e
  } noraise {
    _ => fail("Host proof bypassed the selected authored candidate")
  }
  assert_eq(programs.length(), 0)
}
