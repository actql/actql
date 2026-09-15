///|
// Independently hashed canonical fixture input, not expected conversion output.
fn public_append_claim() -> @wire.ProgramProofClaim {
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let witness = @wire.admit(
    @utf8.encode(
      (
        #|{"dependencies":["sha256:303443716d06c93bfdddc667c9134088a4367e7bbb40e8a931c037ad1cd96b1a","sha256:a7aa58ed1092b375da4a044a6096eb5c3432aea5c8562613081f35c4d962f23d"],"derivation":{"left":"sha256:a7aa58ed1092b375da4a044a6096eb5c3432aea5c8562613081f35c4d962f23d","op":"add","right":"sha256:a7aa58ed1092b375da4a044a6096eb5c3432aea5c8562613081f35c4d962f23d"},"law_id":"actql.bound.append","role":"proven_upper_bound","source":{"kind":"program","proof_cid":"sha256:303443716d06c93bfdddc667c9134088a4367e7bbb40e8a931c037ad1cd96b1a","semantic_ref":"checked-step:0"},"unit":"rows","value":2,"version":"actql-bound-witness/0.1","witness_cid":"sha256:9b48d118a1fce63528097cabfbad8dd2eeab05c8e6cdd22b48081da080798a1c"}
      ),
    ),
    "sha256:9b48d118a1fce63528097cabfbad8dd2eeab05c8e6cdd22b48081da080798a1c",
    caps,
  ).unwrap()
  @wire.bind_program_proof(
    @utf8.encode(
      (
        #|{"inputs":["sha256:a7aa58ed1092b375da4a044a6096eb5c3432aea5c8562613081f35c4d962f23d","sha256:a7aa58ed1092b375da4a044a6096eb5c3432aea5c8562613081f35c4d962f23d"],"law_id":"actql.bound.append","semantic_ref":"checked-step:0","unit":"rows","value":2,"version":"actql-bound-proof/0.1"}
      ),
    ),
    witness,
    caps,
  ).unwrap()
}

///|
test "external consumer retains repeated imported operands and rejects an exhausted check" {
  let program = public_program_fixture(generated=true, repeated=true)
  let publication = @program_check.unit_publication_at(program, 1, 0).unwrap()
  assert_eq(
    @context.publication_row_limit_maximum(
      @program_check.publication_selection(publication),
    ),
    2L,
  )
  let root = @program_check.publication_proof_at(publication, 0).unwrap()
  assert_eq(@program_check.proof_input_count(root), 2)
  let left = @program_check.proof_input_at(root, 0).unwrap()
  let right = @program_check.proof_input_at(root, 1).unwrap()
  assert_true(physical_equal(left, right))
  assert_eq(
    @program_check.proof_source(left).unit_definition_cid,
    @program_check.unit_definition_cid(program, 0).unwrap(),
  )
  assert_eq(
    @wire.program_proof_input_count(@program_check.proof_claim(root)),
    2,
  )
  try public_program_fixture(generated=true, repeated=true, max_work=0) catch {
    @program_check.LocalConstructionFailure::CapacityInputs(BudgetExceeded) =>
      ()
    e => raise e
  } noraise {
    _ => fail("exhausted preparation returned a CheckedProgram")
  }
}

///|
test "external consumer reads persistent imported proof limits and runtime ownership" {
  let program = public_program_fixture(generated=true)
  let producer_cid = @program_check.unit_definition_cid(program, 0).unwrap()
  for stage in 0..<2 {
    let unit_cid = @program_check.unit_definition_cid(program, stage).unwrap()
    let publication = @program_check.unit_publication_at(program, stage, 0).unwrap()
    assert_true(
      @program_check.publication_phase(publication) is BeforeResultPublication,
    )
    assert_true(
      @program_check.publication_failure(publication)
      is PreventResultPublication,
    )
    assert_eq(
      @context.publication_row_limit_maximum(
        @program_check.publication_selection(publication),
      ),
      1L,
    )
    let rows = @program_check.publication_rows(publication)
    assert_eq(
      @wire.limit_subject(rows),
      "unit:" + unit_cid + "#/results/out/rows",
    )
    assert_eq(
      @wire.limit_subject(@program_check.publication_bytes(publication)),
      "unit:" + unit_cid + "#/results/out/bytes",
    )
    let count = @program_check.publication_proof_count(publication)
    assert_true(count > 0)
    for index in 0..<count {
      let proof = @program_check.publication_proof_at(publication, index).unwrap()
      let location = @program_check.proof_source(proof)
      assert_eq(location.unit_definition_cid, producer_cid)
      assert_eq(location.source_ordinal, 0)
      let claim = @program_check.proof_claim(proof)
      let witness = @wire.program_proof_witness(claim)
      assert_eq(@wire.value(witness), 1L)
      assert_eq(@program_check.proof_input_count(proof), 0)
      assert_eq(@program_check.proof_graph_input_count(proof), 0)
      assert_eq(@program_check.proof_external_input_count(proof), 0)
      assert_true(@program_check.proof_input_at(proof, 0) is None)
      assert_true(
        physical_equal(
          @step_bounds.checked_pipeline(@program_check.proof_application(proof)),
          @program_check.unit_pipeline(program, 0).unwrap(),
        ),
      )
    }
    assert_true(@program_check.publication_proof_at(publication, count) is None)
    // This Local-only Program has no SourceView publication policy. Absence is
    // explicit, not a synthetic policy attestation inferred from a row proof.
    assert_true(@program_check.publication_source_policy(publication) is None)
  }
  let input = @program_check.unit_input_completeness(program, 1, 0).unwrap()
  guard input.binding is Imported(interface, producer) else {
    fail("import binding lost")
  }
  assert_eq(interface.producer_unit_definition_cid, producer_cid)
  assert_true(
    physical_equal(
      @pipeline.producer_pipeline(producer),
      @program_check.unit_pipeline(program, 0).unwrap(),
    ),
  )
  assert_true(@program_check.unit_input_completeness(program, 0, 0) is None)
  let other = public_program_fixture(generated=true)
  assert_eq(@program_check.unit_definition_cid(other, 0), Some(producer_cid))
  let proof = @program_check.publication_proof_at(
    @program_check.unit_publication_at(program, 1, 0).unwrap(),
    0,
  ).unwrap()
  let bound = @program_check.proof_application(proof)
  assert_true(
    @step_bounds.check_target_rows(
      @program_check.unit_pipeline(program, 0).unwrap(),
      Step(0),
      bound,
      10000,
    )
    is Ok(_),
  )
  assert_true(
    @step_bounds.check_target_rows(
      @program_check.unit_pipeline(other, 0).unwrap(),
      Step(0),
      bound,
      10000,
    )
    is Err(_),
  )
}

///|
fn public_seed_claim() -> @wire.ProgramProofClaim {
  let limits : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let witness = @wire.admit(
    @utf8.encode(
      "{\"dependencies\":[\"sha256:02fa1dd5e32fc11c42454c3e573531ad747e164ee12d88921206650b45014033\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.values\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:02fa1dd5e32fc11c42454c3e573531ad747e164ee12d88921206650b45014033\",\"semantic_ref\":\"checked-step:0\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:a7aa58ed1092b375da4a044a6096eb5c3432aea5c8562613081f35c4d962f23d\"}",
    ),
    "sha256:a7aa58ed1092b375da4a044a6096eb5c3432aea5c8562613081f35c4d962f23d",
    limits,
  ).unwrap()
  @wire.bind_program_proof(
    @utf8.encode(
      "{\"inputs\":[],\"law_id\":\"actql.bound.values\",\"semantic_ref\":\"checked-step:0\",\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-proof/0.1\"}",
    ),
    witness,
    limits,
  ).unwrap()
}

///|
test "compilation work does not select a different runtime capacity or identity" {
  let first = public_program_fixture()
  let second = public_program_fixture(max_work=20000000)
  for stage in 0..<2 {
    assert_eq(
      @program_check.unit_definition_cid(first, stage),
      @program_check.unit_definition_cid(second, stage),
    )
    let a = @program_check.unit_publication_at(first, stage, 0).unwrap()
    let b = @program_check.unit_publication_at(second, stage, 0).unwrap()
    assert_eq(
      @wire.limit_cid(@program_check.publication_rows(a)),
      @wire.limit_cid(@program_check.publication_rows(b)),
    )
    assert_eq(
      @wire.limit_cid(@program_check.publication_bytes(a)),
      @wire.limit_cid(@program_check.publication_bytes(b)),
    )
  }
}

///|
