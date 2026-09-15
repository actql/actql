///|
test "standard check constructs the repeated imported append capacity proof" {
  let (_, parsed, environment, evidence, limits) = public_input_fixture(
    generated=true,
    repeated=true,
  )
  let automatic = public_checked(
    @program_check.check_parsed(parsed, environment, None, limits),
  )
  let supplied = public_checked(
    @program_check.check_parsed_with_evidence(
      parsed,
      environment,
      None,
      evidence,
      limits,
    ),
  )
  // Independent canonical-JSON/SHA fixture: values pair606/22 and repeated
  // append pair987/27. Supplied admitted bodies require no re-emission.
  assert_eq(
    @context.program_identity_capacity_metadata_usage(
      @program_check.source_identity(automatic),
    ),
    (1593, 49),
  )
  assert_eq(
    @context.program_identity_capacity_metadata_usage(
      @program_check.source_identity(supplied),
    ),
    (0, 0),
  )
  let published = @program_check.unit_publication_at(automatic, 1, 0).unwrap()
  // The one-row producer occurs twice in append. Distinct can reduce that
  // output but cannot increase it. This is a bound, not a claim of two rows.
  assert_eq(
    @context.publication_row_limit_maximum(
      @program_check.publication_selection(published),
    ),
    2L,
  )
  let explicit = @program_check.unit_publication_at(supplied, 1, 0).unwrap()
  assert_eq(
    @wire.limit_cid(@program_check.publication_rows(published)),
    @wire.limit_cid(@program_check.publication_rows(explicit)),
  )
  for stage in 0..<2 {
    assert_eq(
      @program_check.unit_definition_cid(automatic, stage),
      @program_check.unit_definition_cid(supplied, stage),
    )
  }
}

///|
test "automatic append construction shares Result demands and skips unused append proofs" {
  let (text, _, environment, _, limits) = public_input_fixture(
    generated=true,
    repeated=true,
  )
  let limits = {
    ..limits,
    compilation: {
      ..limits.compilation,
      structure: { ..limits.compilation.structure, results: 3, },
    },
  }
  let repeated = text.replace(
    old="\"out\":{\"from\":\"selected\",\"fields\":[\"id\",\"value\"]}",
    new="\"out\":{\"from\":\"selected\",\"fields\":[\"id\",\"value\"]},\"again\":{\"from\":\"selected\",\"fields\":[\"id\",\"value\"]}",
  )
  let program = public_checked(
    @program_check.check_document(
      repeated,
      environment,
      None,
      limits,
      format=Json,
    ),
  )
  assert_eq(
    @context.program_identity_capacity_metadata_usage(
      @program_check.source_identity(program),
    ),
    (1593, 49),
  )
  for i in 0..<2 {
    let publication = @program_check.unit_publication_at(program, 1, i).unwrap()
    assert_eq(
      @context.publication_row_limit_maximum(
        @program_check.publication_selection(publication),
      ),
      2L,
    )
  }
  let unused = text.replace(
    old="{\"distinct\":[\"id\",\"value\"],\"as\":\"selected\"}",
    new="{\"from\":\"rows\",\"distinct\":[\"id\",\"value\"],\"as\":\"selected\"}",
  )
  let program = public_checked(
    @program_check.check_document(
      unused,
      environment,
      None,
      limits,
      format=Json,
    ),
  )
  assert_eq(
    @context.program_identity_capacity_metadata_usage(
      @program_check.source_identity(program),
    ),
    (606, 22),
  )
  let publication = @program_check.unit_publication_at(program, 1, 0).unwrap()
  assert_eq(
    @context.publication_row_limit_maximum(
      @program_check.publication_selection(publication),
    ),
    1L,
  )
}

///|
test "automatic append binds local and imported equal-CID count occurrences separately" {
  let (text, _, environment, _, limits) = public_input_fixture(
    generated=true,
    repeated=true,
  )
  let limits = {
    ..limits,
    compilation: {
      ..limits.compilation,
      structure: { ..limits.compilation.structure, steps: 6, },
    },
  }
  let source = text.replace(
    old="{\"append\":{\"with\":\"rows\"}}",
    new="{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2,\"value\":3}]},\"as\":\"local\"},{\"append\":{\"with\":\"rows\"}}",
  )
  let program = public_checked(
    @program_check.check_document(
      source,
      environment,
      None,
      limits,
      format=Json,
    ),
  )
  let publication = @program_check.unit_publication_at(program, 1, 0).unwrap()
  assert_eq(
    @context.publication_row_limit_maximum(
      @program_check.publication_selection(publication),
    ),
    2L,
  )
  assert_eq(@program_check.publication_proof_count(publication), 1)
  let proof = @program_check.publication_proof_at(publication, 0).unwrap()
  assert_eq(@program_check.proof_input_count(proof), 2)
  let left = @program_check.proof_input_at(proof, 0).unwrap()
  let right = @program_check.proof_input_at(proof, 1).unwrap()
  assert_eq(
    @program_check.proof_source(left).unit_definition_cid,
    @program_check.unit_definition_cid(program, 1).unwrap(),
  )
  assert_eq(
    @program_check.proof_source(right).unit_definition_cid,
    @program_check.unit_definition_cid(program, 0).unwrap(),
  )
  let left_id = @wire.cid(
    @wire.program_proof_witness(@program_check.proof_claim(left)),
  )
  let right_id = @wire.cid(
    @wire.program_proof_witness(@program_check.proof_claim(right)),
  )
  assert_true(left_id != right_id)
  assert_true(
    @wire.derivation(
      @wire.program_proof_witness(@program_check.proof_claim(proof)),
    )
    is Add(a, b) &&
    a == left_id &&
    b == right_id,
  )
}
