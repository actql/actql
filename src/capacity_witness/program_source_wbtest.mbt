///|
// Independent full preimages are retained in fixed fixtures; no product output
// is used to obtain their expected hashes.
fn typed_program_source_vectors() -> Array[
  (String, Int64, @arithmetic.BoundUnit, String, String, String, String),
] {
  [
    (
      "step:0",
      2L,
      @arithmetic.Rows,
      "actql.bound.append",
      "{\"inputs\":[],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:ac2f5270372530381a80fda7a7d5a5f374e5dae82604058adda2fe969ec9b56b\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:ac2f5270372530381a80fda7a7d5a5f374e5dae82604058adda2fe969ec9b56b\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:f29874a0ccc16dcff3a379b4002226c157d45fa939162bc802e20abbccb06595\"}",
      "sha256:f29874a0ccc16dcff3a379b4002226c157d45fa939162bc802e20abbccb06595",
    ),
    (
      "checked-step:0",
      25L,
      @arithmetic.Bytes,
      "actql.bound.values-wire",
      "{\"inputs\":[],\"law_id\":\"actql.bound.values-wire\",\"semantic_ref\":\"checked-step:0\",\"unit\":\"bytes\",\"value\":25,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:7c87aa9e1a77cbf8368b652fa15d7fde2ee5bf4ca280d55621c0cd71033bf22b\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.values-wire\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:7c87aa9e1a77cbf8368b652fa15d7fde2ee5bf4ca280d55621c0cd71033bf22b\",\"semantic_ref\":\"checked-step:0\"},\"unit\":\"bytes\",\"value\":25,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:15622500b68d7891fc269aca0d7cb37561307a912578cd88f3d2dadcc54fb56e\"}",
      "sha256:15622500b68d7891fc269aca0d7cb37561307a912578cd88f3d2dadcc54fb56e",
    ),
    (
      "step:é/\"x",
      9007199254740991L,
      @arithmetic.Nodes,
      "actql.bound.graph-input-nodes",
      "{\"inputs\":[],\"law_id\":\"actql.bound.graph-input-nodes\",\"semantic_ref\":\"step:é/\\\"x\",\"unit\":\"nodes\",\"value\":9007199254740991,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:b8aa6af3c248d18ced1706a596cb43838c5e340b6c50b5e38f4b47b615ec341a\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:b8aa6af3c248d18ced1706a596cb43838c5e340b6c50b5e38f4b47b615ec341a\",\"semantic_ref\":\"step:é/\\\"x\"},\"unit\":\"nodes\",\"value\":9007199254740991,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:53b063e31d5c60f16fe75358b8c34802fbc0fd200fa169994d35c5cad3828489\"}",
      "sha256:53b063e31d5c60f16fe75358b8c34802fbc0fd200fa169994d35c5cad3828489",
    ),
  ]
}

///|
test "typed Program source preserves independent proof and complete witness identities" {
  let limits : Limits = { max_bytes: 8192, max_nodes: 100, max_depth: 10, }
  for
    (subject, value, unit, law, proof_text, wire_text, expected) in typed_program_source_vectors() {
    let claim = create_program_source(
      subject,
      value,
      unit,
      @law.admit(law).unwrap(),
      limits,
    ).unwrap()
    let witness = program_proof_witness(claim)
    assert_true(witness.body is ProgramSourceValue)
    assert_eq(program_proof_form(claim), DerivedInputs)
    assert_eq(program_proof_input_count(claim), 0)
    assert_eq(cid(witness), expected)
    let out = @encode.writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit(witness, out)
    assert_eq(@encode.finish(out), wire_text)
    let external = admit(@utf8.encode(wire_text), expected, limits).unwrap()
    assert_true(external.body is Parsed(_))
    let bound = bind_program_proof(@utf8.encode(proof_text), external, limits).unwrap()
    assert_eq(cid(program_proof_witness(bound)), expected)
    assert_true(
      same_witness_body(typed_host_source_candidate(wire_text), witness),
    )
    for
      changed in [
        wire_text.replace(old="proven_upper_bound", new="host_ceiling"),
        wire_text.replace(
          old="\"op\":\"source\"",
          new="\"extra\":true,\"op\":\"source\"",
        ),
        wire_text.replace(old="semantic_ref", new="foreign_ref"),
      ] {
      assert_false(
        same_witness_body(typed_host_source_candidate(changed), witness),
      )
      assert_true(admit(@utf8.encode(changed), expected, limits) is Err(_))
    }
  }
}

///|
test "typed Program source enforces full wire bounds and exact nonnegative safe integers" {
  for
    (subject, value, unit, law, _, wire_text, _) in typed_program_source_vectors() {
    let wide : Limits = { max_bytes: 8192, max_nodes: 100, max_depth: 10, }
    let law = @law.admit(law).unwrap()
    let witness = program_proof_witness(
      create_program_source(subject, value, unit, law, wide).unwrap(),
    )
    let out = @encode.measuring_writer(
      wide.max_bytes,
      wide.max_nodes,
      wide.max_depth,
    )
    emit(witness, out)
    let (bytes, nodes, depth) = @encode.finish_measurement_usage(out)
    assert_eq(bytes, @utf8.encode(wire_text).length())
    let exact : Limits = {
      max_bytes: bytes,
      max_nodes: nodes,
      max_depth: depth,
    }
    assert_true(
      create_program_source(subject, value, unit, law, exact) is Ok(_),
    )
    for
      short in [
        { ..exact, max_bytes: bytes - 1, },
        { ..exact, max_nodes: nodes - 1, },
        { ..exact, max_depth: depth - 1, },
      ] {
      assert_true(
        create_program_source(subject, value, unit, law, short)
        is Err(BudgetExceeded),
      )
    }
    assert_true(
      create_program_source(subject, value, unit, law, {
        ..exact,
        max_bytes: -1,
      })
      is Err(InvalidLimits),
    )
    assert_true(
      create_program_source("", value, unit, law, wide) is Err(InvalidWitness),
    )
    for invalid in [-1L, 9007199254740992L] {
      assert_true(
        create_program_source(subject, invalid, unit, law, wide)
        is Err(InvalidWitness),
      )
    }
  }
}
