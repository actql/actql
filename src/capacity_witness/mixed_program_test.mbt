// Independent Node proof and witness CIDs, not semantic source attestations.

///|
fn mixed_program_fixture(kind : Int) -> (WireWitness, ProgramProofClaim) {
  let (body, id, proof) = match kind {
    0 =>
      (
        "{\"dependencies\":[\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\",\"sha256:ae7bae27107c361f6f167361d8c1e5dbc80345830622967ce730000f9ed4c3d6\"],\"derivation\":{\"input\":\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\",\"op\":\"preserve\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:ae7bae27107c361f6f167361d8c1e5dbc80345830622967ce730000f9ed4c3d6\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1f1b9705bcfd8b09d5e320853df393a45de22cb89f614794e42906b61e7f039b\"}",
        "sha256:1f1b9705bcfd8b09d5e320853df393a45de22cb89f614794e42906b61e7f039b",
        "{\"inputs\":[\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\"],\"law_id\":\"actql.bound.graph-input-nodes\",\"semantic_ref\":\"g\",\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-proof/0.1\"}",
      )
    1 =>
      (
        "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:a639df62e4abb466eb94770c58e44711171e16faf29ed967240af991a52c860b\",\"sha256:ed70362796bb6a215d48d55cd53238fc886051726bdf372b40a4fba4e2568a1a\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:a639df62e4abb466eb94770c58e44711171e16faf29ed967240af991a52c860b\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:eaabb2f603fbce25b434379b7be9297db2cd0feab466467ce515a5471f4ec3e5\"}",
        "sha256:eaabb2f603fbce25b434379b7be9297db2cd0feab466467ce515a5471f4ec3e5",
        "{\"dependencies\":[\"sha256:ed70362796bb6a215d48d55cd53238fc886051726bdf372b40a4fba4e2568a1a\",\"sha256:ed70362796bb6a215d48d55cd53238fc886051726bdf372b40a4fba4e2568a1a\"],\"law_id\":\"actql.bound.graph-input-nodes\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"g\",\"unit\":\"nodes\",\"value\":5,\"version\":\"actql-bound-proof/0.1\"}",
      )
    2 =>
      (
        "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"sha256:8fb0b7df41e2d6a33c2bc9b2996aaf0ee499fed5342a095a524b6b5c1487929a\",\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:8fb0b7df41e2d6a33c2bc9b2996aaf0ee499fed5342a095a524b6b5c1487929a\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:52f6c61140fd390c06d1718a8132ac8f405f69f858da67c10b9a0f6f21d9cd5a\"}",
        "sha256:52f6c61140fd390c06d1718a8132ac8f405f69f858da67c10b9a0f6f21d9cd5a",
        "{\"dependencies\":[\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\"],\"law_id\":\"actql.bound.graph-input-nodes\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"semantic_ref\":\"g\",\"unit\":\"nodes\",\"value\":5,\"version\":\"actql-bound-proof/0.1\"}",
      )
    3 =>
      (
        "{\"dependencies\":[\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\",\"sha256:e8d8e8a397eaacf1a96f7ce7afc32fde28a7bb30a4f70fd7fc5eb09b0370752f\"],\"derivation\":{\"input\":\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\",\"op\":\"preserve\"},\"law_id\":\"actql.bound.graph-input-nodes\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:e8d8e8a397eaacf1a96f7ce7afc32fde28a7bb30a4f70fd7fc5eb09b0370752f\",\"semantic_ref\":\"g\"},\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:afb5502b187c1964a4abe5756fbb15889544e84fdd7abf1b434fce40a6812880\"}",
        "sha256:afb5502b187c1964a4abe5756fbb15889544e84fdd7abf1b434fce40a6812880",
        "{\"inputs\":[\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\",\"sha256:a17643523bec58669401785faa766f74f74c7fadd5f2af8e581c04e621138b11\"],\"law_id\":\"actql.bound.graph-input-nodes\",\"semantic_ref\":\"g\",\"unit\":\"nodes\",\"value\":10,\"version\":\"actql-bound-proof/0.1\"}",
      )
    _ => abort("unknown fixture")
  }
  let witness = claim_fixture(body, id)
  let proof = bind_program_proof(@utf8.encode(proof), witness, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 5,
  }).unwrap()
  (witness, proof)
}

///|
test "combined closure retains mixed limits and all Program input occurrences" {
  let w = mixed_witnesses()
  let (preserved, p1) = mixed_program_fixture(0)
  let (source, p2) = mixed_program_fixture(1)
  w[1] = preserved
  w.push(source)
  let mixed = check_mixed_claims(w, mixed_artifacts(), mixed_caps()).unwrap()
  let result = check_mixed_program_claims(mixed, [p2, p1], {
    max_witnesses: 10,
    max_references: 100,
  }).unwrap()
  assert_true(physical_equal(program_claim_mixed(result).unwrap(), mixed))
  assert_true(
    physical_equal(program_claim_arithmetic(result), mixed_arithmetic(mixed)),
  )
  assert_eq(
    check_program_claims(mixed_arithmetic(mixed), [p1, p2], {
      max_witnesses: 10,
      max_references: 100,
    }).unwrap_err(),
    MissingProgramProof(0),
  )
  assert_true(physical_equal(program_claim_proof_at(result, 1).unwrap(), p1))
  assert_true(physical_equal(program_claim_proof_at(result, 5).unwrap(), p2))
  assert_true(program_claim_proof_at(result, 0) is None)
  assert_eq(
    program_proof_input_count(program_claim_proof_at(result, 5).unwrap()),
    2,
  )
  let references = mixed_usage(mixed).0 + 3
  assert_eq(program_claim_reference_count(result), references)
  assert_true(
    check_mixed_program_claims(mixed, [p1, p2], {
      max_witnesses: 10,
      max_references: references,
    })
    is Ok(_),
  )
  assert_eq(
    check_mixed_program_claims(mixed, [p1, p2], {
      max_witnesses: 9,
      max_references: references,
    }).unwrap_err(),
    ProgramBudgetExceeded,
  )
  assert_eq(
    check_mixed_program_claims(mixed, [p1, p2], {
      max_witnesses: 10,
      max_references: references - 1,
    }).unwrap_err(),
    ProgramBudgetExceeded,
  )
  assert_eq(
    check_mixed_program_claims(mixed, [p1], {
      max_witnesses: 10,
      max_references: 100,
    }).unwrap_err(),
    MissingProgramProof(5),
  )
  assert_eq(
    check_mixed_program_claims(mixed, [p1, p1], {
      max_witnesses: 10,
      max_references: 100,
    }).unwrap_err(),
    DuplicateProgramProof(1),
  )
}

///|
test "combined closure rejects hidden Program input and operand mismatches" {
  for
    (kind, expected) in [
      (
        2,
        ProgramClosureIssue::MissingProgramInput(5, "sha256:" + "f".repeat(64)),
      ),
      (3, ProgramClosureIssue::ProgramOperandMismatch(1)),
    ] {
    let w = mixed_witnesses()
    let (normal, p1) = mixed_program_fixture(0)
    let (bad, proof) = mixed_program_fixture(kind)
    w[1] = normal
    let proofs = if kind == 2 {
      w.push(bad)
      [p1, proof]
    } else {
      w[1] = bad
      [proof]
    }
    let mixed = check_mixed_claims(w, mixed_artifacts(), mixed_caps()).unwrap()
    assert_eq(
      check_mixed_program_claims(mixed, proofs, {
        max_witnesses: 20,
        max_references: 100,
      }).unwrap_err(),
      expected,
    )
  }
  let mixed = check_mixed_claims([mixed_witnesses()[3]], [], mixed_caps()).unwrap()
  assert_eq(
    check_mixed_program_claims(mixed, [mixed_program_fixture(0).1], {
      max_witnesses: 20,
      max_references: 100,
    }).unwrap_err(),
    ForeignProgramProof(0),
  )
}
