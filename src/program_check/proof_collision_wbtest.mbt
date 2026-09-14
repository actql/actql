///|
test "persistent append operands distinguish equal local CIDs by owned occurrence" {
  for repeated in [false, true] {
    let programs : Array[CheckedProgram] = []
    ignore(
      local_construction_fixture(
        { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
        second_stage=true,
        through_check=true,
        checked_results=programs,
        generated_rows=Some("[{\"id\":1}]"),
        second_steps="[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2,\"value\":3}]},\"as\":\"local\"},{\"append\":{\"with\":\"" +
          (if repeated { "local" } else { "rows" }) +
          "\"}},{\"distinct\":[\"id\",\"value\"],\"as\":\"selected\"}]",
        second_result_from="selected",
        extra_step_budget=10,
      ),
    )
    let program = programs[0]
    let seed = keyed_sourceview_claim()
    let local_bound = @step_bounds.check(program.units[1].pipeline, 0, seed).unwrap()
    let producer = if repeated {
      local_bound
    } else {
      @step_bounds.check(program.units[0].pipeline, 0, seed).unwrap()
    }
    let cid = @wire.cid(@wire.program_proof_witness(seed))
    let added = collision_append_claim(cid)
    let bound = @step_bounds.check_with_inputs(
      program.units[1].pipeline,
      1,
      added,
      [local_bound, producer],
      max_input_work=1000,
    ).unwrap()
    let converted = reidentify_step_graph(program.units, bound, {
      work: 100000000,
      bytes: 10000000,
      nodes: 1000000,
      depth: 100,
    })
    assert_eq(converted.inputs.length(), 2)
    let left = @wire.cid(@wire.program_proof_witness(converted.inputs[0].proof))
    let right = @wire.cid(
      @wire.program_proof_witness(converted.inputs[1].proof),
    )
    assert_eq(left == right, repeated)
    assert_eq(
      physical_equal(converted.inputs[0], converted.inputs[1]),
      repeated,
    )
    assert_true(
      @wire.derivation(@wire.program_proof_witness(converted.proof))
      is Add(a, b) &&
      a == left &&
      b == right,
    )
    assert_eq(@wire.program_proof_input_count(converted.proof), 2)
    // The independent arithmetic/admission boundary checks the rebuilt graph,
    // not just the emitter's self-CID. Registry deduplication does not change
    // the two input occurrences retained in the root proof.
    let proofs = [converted.inputs[0].proof, converted.proof]
    if !repeated {
      proofs.push(converted.inputs[1].proof)
    }
    let claims = @wire.check_mixed_claims(
      proofs.map(p => @wire.program_proof_witness(p)),
      [],
      {
        max_entities: 100,
        max_references: 100,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
    ).unwrap()
    assert_true(
      @wire.check_mixed_program_claims(claims, proofs, {
        max_witnesses: 100,
        max_references: 100,
      })
      is Ok(_),
    )
    assert_eq(
      converted.inputs[0].location.unit_definition_cid,
      unit_definition_cid(program, 1).unwrap(),
    )
    assert_eq(
      converted.inputs[1].location.unit_definition_cid,
      unit_definition_cid(program, if repeated { 1 } else { 0 }).unwrap(),
    )
  }
}

///|
fn collision_append_claim(input : String) -> @wire.ProgramProofClaim {
  // Input artifact hashes only; expected converted operands come from their
  // distinct checked owner positions, never from a conversion output fixture.
  let proof = "{\"inputs\":[\"\{input}\",\"\{input}\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"checked-step:1\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}"
  let proof_cid = "sha256:" + @sha.hex(@utf8.encode(proof))
  let dependencies = if input < proof_cid {
    "[\"\{input}\",\"\{proof_cid}\"]"
  } else {
    "[\"\{proof_cid}\",\"\{input}\"]"
  }
  let body = "{\"dependencies\":\{dependencies},\"derivation\":{\"left\":\"\{input}\",\"op\":\"add\",\"right\":\"\{input}\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"\{proof_cid}\",\"semantic_ref\":\"checked-step:1\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\""
  let cid = "sha256:" + @sha.hex(@utf8.encode(body + "}"))
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let witness = @wire.admit(
    @utf8.encode(body + ",\"witness_cid\":\"\{cid}\"}"),
    cid,
    caps,
  ).unwrap()
  @wire.bind_program_proof(@utf8.encode(proof), witness, caps).unwrap()
}
