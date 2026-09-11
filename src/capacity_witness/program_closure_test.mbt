// Independent Node crypto fixtures. Law applicability and Host authority are
// intentionally not claimed by these arithmetic/proof-closure tests.

///|
fn program_fixture_claims() -> (Array[WireWitness], Array[ProgramProofClaim]) {
  let limits : Limits = { max_bytes: 10000, max_nodes: 100, max_depth: 10, }
  let host = admit(
    @utf8.encode(
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.artifact-rows\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_artifact_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"},\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"}",
    ),
    "sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692",
    limits,
  ).unwrap()
  let fixtures = [
    (
      "{\"dependencies\":[\"sha256:79925c5c186d7bf8e7e87ae05db90f147177687ba4c72e85b1e6854f66f1af97\",\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"derivation\":{\"left\":\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"op\":\"add\",\"right\":\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:79925c5c186d7bf8e7e87ae05db90f147177687ba4c72e85b1e6854f66f1af97\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":6,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:2d6910f82027166f5294a824523bc165497950ceec8e067b78c268a2c86ae2c6\"}",
      "sha256:2d6910f82027166f5294a824523bc165497950ceec8e067b78c268a2c86ae2c6",
      "{\"inputs\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":6,\"version\":\"actql-bound-proof/0.1\"}",
    ),
    (
      "{\"dependencies\":[\"sha256:48d4978f75f580488632b1c681f58179e869e3d99d6c664367826544ec04d577\",\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"derivation\":{\"inputs\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"op\":\"min\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:48d4978f75f580488632b1c681f58179e869e3d99d6c664367826544ec04d577\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:36c84714b28c6e77c185730b2ddc84b320f72fdf99bbc5667d926fd2730b642b\"}",
      "sha256:36c84714b28c6e77c185730b2ddc84b320f72fdf99bbc5667d926fd2730b642b",
      "{\"inputs\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-proof/0.1\"}",
    ),
    (
      "{\"dependencies\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"sha256:e28089be762aafb3fadffbfe3571676d08d55a607cb5e918fb064830a1843298\"],\"derivation\":{\"factor\":2,\"input\":\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"op\":\"multiply\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:e28089be762aafb3fadffbfe3571676d08d55a607cb5e918fb064830a1843298\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":6,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:8d37301d8b89529959bfcf64e9b0979048661895095b7d72493b2129a8acae8c\"}",
      "sha256:8d37301d8b89529959bfcf64e9b0979048661895095b7d72493b2129a8acae8c",
      "{\"inputs\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":6,\"version\":\"actql-bound-proof/0.1\"}",
    ),
    (
      "{\"dependencies\":[\"sha256:bc48fc111e1f36d3a64200fe1ae29ed284aa3c37e833edc68b765553de4c8299\"],\"derivation\":{\"maximum\":5,\"op\":\"clamp\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:bc48fc111e1f36d3a64200fe1ae29ed284aa3c37e833edc68b765553de4c8299\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:713eccab85f655607564a4a15a1b5e8efe824d7127bce5a49fac2971c3d2553f\"}",
      "sha256:713eccab85f655607564a4a15a1b5e8efe824d7127bce5a49fac2971c3d2553f",
      "{\"inputs\":[],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":5,\"version\":\"actql-bound-proof/0.1\"}",
    ),
    (
      "{\"dependencies\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"sha256:e86e10c814973055881415517a25371456ebef3dcde02dded0f34b67ab83b5ce\"],\"derivation\":{\"input\":\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"maximum\":2,\"op\":\"clamp\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:e86e10c814973055881415517a25371456ebef3dcde02dded0f34b67ab83b5ce\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:77045c11587a4bae0507c330402376186648412fcfa2ae79364baf2cf0bb9b06\"}",
      "sha256:77045c11587a4bae0507c330402376186648412fcfa2ae79364baf2cf0bb9b06",
      "{\"inputs\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
    ),
    (
      "{\"dependencies\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"sha256:b280859f81e38dcb3dbda1163dfba2ccdc882c4fd3de63cd24ef62139839f245\"],\"derivation\":{\"input\":\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"op\":\"preserve\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:b280859f81e38dcb3dbda1163dfba2ccdc882c4fd3de63cd24ef62139839f245\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:3f38871bf307186b5bc7534410f96446a7dcbb896d5f9187ca060076cf113a28\"}",
      "sha256:3f38871bf307186b5bc7534410f96446a7dcbb896d5f9187ca060076cf113a28",
      "{\"inputs\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-proof/0.1\"}",
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000002\",\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"sha256:a92e3cda7c9d898d67e37eb9f685b95a5879c4be58bf5f7418961882af089e2c\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:a92e3cda7c9d898d67e37eb9f685b95a5879c4be58bf5f7418961882af089e2c\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:8862d53c77fee26023c483bf965eeae7c44f4af2403abca9f857688a16cfa65b\"}",
      "sha256:8862d53c77fee26023c483bf965eeae7c44f4af2403abca9f857688a16cfa65b",
      "{\"dependencies\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"law_id\":\"actql.bound.append\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000002\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-proof/0.1\"}",
    ),
  ]
  let witnesses = []
  let proofs = []
  for f in fixtures {
    let (wire, cid, body) = f
    let witness = admit(@utf8.encode(wire), cid, limits).unwrap()
    witnesses.push(witness)
    proofs.push(
      bind_program_proof(@utf8.encode(body), witness, limits).unwrap(),
    )
  }
  witnesses.push(host)
  (witnesses, proofs)
}

///|
test "Program proof closure resolves forward repeated and source input dependencies" {
  let (witnesses, proofs) = program_fixture_claims()
  let arithmetic = check_arithmetic_claims(witnesses, {
    max_witnesses: 100,
    max_references: 1000,
  }).unwrap()
  let mut references = claim_reference_count(arithmetic)
  for proof in proofs {
    references = references + program_proof_input_count(proof)
  }
  let limits : ClosureLimits = {
    max_witnesses: witnesses.length() + proofs.length(),
    max_references: references,
  }
  let reversed = Array::makei(proofs.length(), i => {
    proofs[proofs.length() - 1 - i]
  })
  let checked = check_program_claims(arithmetic, reversed, limits).unwrap()
  assert_eq(program_claim_reference_count(checked), references)
  assert_eq(claim_count(program_claim_arithmetic(checked)), witnesses.length())
  for i, witness in witnesses {
    match program_claim_proof_at(checked, i) {
      Some(proof) => assert_eq(cid(program_proof_witness(proof)), cid(witness))
      None => assert_eq(i, witnesses.length() - 1)
    }
  }
  assert_true(program_claim_proof_at(checked, -1) is None)
  assert_true(program_claim_proof_at(checked, witnesses.length()) is None)
  reversed.clear()
  witnesses.clear()
  assert_true(program_claim_proof_at(checked, 0) is Some(_))
  assert_true(
    check_program_claims(arithmetic, proofs, {
      ..limits,
      max_witnesses: limits.max_witnesses - 1,
    })
    is Err(ProgramBudgetExceeded),
  )
  assert_true(
    check_program_claims(arithmetic, proofs, {
      ..limits,
      max_references: references - 1,
    })
    is Err(ProgramBudgetExceeded),
  )
  assert_true(
    check_program_claims(arithmetic, proofs, { ..limits, max_references: -1, })
    is Err(InvalidProgramLimits),
  )
}

///|
test "Program closure requires every proof and rejects duplicate or foreign bodies" {
  let (witnesses, proofs) = program_fixture_claims()
  let limits : ClosureLimits = { max_witnesses: 100, max_references: 1000, }
  let arithmetic = check_arithmetic_claims(witnesses, limits).unwrap()
  assert_true(
    check_program_claims(arithmetic, [], limits) is Err(MissingProgramProof(0)),
  )
  let missing = proofs.copy()
  ignore(missing.pop())
  assert_true(
    check_program_claims(arithmetic, missing, limits)
    is Err(MissingProgramProof(6)),
  )
  let repeated = proofs.copy()
  repeated.push(proofs[0])
  assert_true(
    check_program_claims(arithmetic, repeated, limits)
    is Err(DuplicateProgramProof(7)),
  )
  let host_only = check_arithmetic_claims(
    [witnesses[witnesses.length() - 1]],
    limits,
  ).unwrap()
  assert_true(
    check_program_claims(host_only, proofs, limits)
    is Err(ForeignProgramProof(0)),
  )
  assert_true(check_program_claims(host_only, [], limits) is Ok(_))
}

///|
test "Program closure rejects mismatched operand multiplicity and unresolved source inputs" {
  let (witnesses, _) = program_fixture_claims()
  let host = witnesses[witnesses.length() - 1]
  let fixtures : Array[(String, String, String, ProgramClosureIssue)] = [
    (
      "{\"dependencies\":[\"sha256:48d4978f75f580488632b1c681f58179e869e3d99d6c664367826544ec04d577\",\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"derivation\":{\"input\":\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"op\":\"preserve\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:48d4978f75f580488632b1c681f58179e869e3d99d6c664367826544ec04d577\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:47cd9d5dad9b390df4b17878a1b6e9821d1de82ebfeec5d543ef6ba458c76e06\"}",
      "sha256:47cd9d5dad9b390df4b17878a1b6e9821d1de82ebfeec5d543ef6ba458c76e06",
      "{\"inputs\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-proof/0.1\"}",
      ProgramOperandMismatch(0),
    ),
    (
      "{\"dependencies\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"sha256:e28089be762aafb3fadffbfe3571676d08d55a607cb5e918fb064830a1843298\"],\"derivation\":{\"left\":\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\",\"op\":\"add\",\"right\":\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:e28089be762aafb3fadffbfe3571676d08d55a607cb5e918fb064830a1843298\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":6,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:f00180dba6871cea714ac8e1a5dbbd5c4b49ad8587a4a3a268c44303260fe9ca\"}",
      "sha256:f00180dba6871cea714ac8e1a5dbbd5c4b49ad8587a4a3a268c44303260fe9ca",
      "{\"inputs\":[\"sha256:91f43a6bd3cefad4a142582928725d7d61688dfd3a20d4fcc6620d7a0a6f3692\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":6,\"version\":\"actql-bound-proof/0.1\"}",
      ProgramOperandMismatch(0),
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000002\",\"sha256:0000000000000000000000000000000000000000000000000000000000000009\",\"sha256:e704e941a64c14e5de2f1a50b44b146a10f99234acdc75a8c958a98612c5fad2\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:e704e941a64c14e5de2f1a50b44b146a10f99234acdc75a8c958a98612c5fad2\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:66b8e42def19421087b34a5908a6b9c22d78e613b0bc2ae7c43fa2a8b78ac67c\"}",
      "sha256:66b8e42def19421087b34a5908a6b9c22d78e613b0bc2ae7c43fa2a8b78ac67c",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000009\"],\"law_id\":\"actql.bound.append\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000002\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-proof/0.1\"}",
      MissingProgramInput(
        0, "sha256:0000000000000000000000000000000000000000000000000000000000000009",
      ),
    ),
  ]
  for f in fixtures {
    let (wire, cid, body, expected) = f
    let limits : Limits = { max_bytes: 10000, max_nodes: 100, max_depth: 10, }
    let witness = admit(@utf8.encode(wire), cid, limits).unwrap()
    let proof = bind_program_proof(@utf8.encode(body), witness, limits).unwrap()
    let closure_limits : ClosureLimits = {
      max_witnesses: 100,
      max_references: 1000,
    }
    let arithmetic = check_arithmetic_claims([witness, host], closure_limits).unwrap()
    match check_program_claims(arithmetic, [proof], closure_limits) {
      Err(actual) => assert_eq(actual, expected)
      Ok(_) => fail("invalid Program closure accepted")
    }
  }
}
