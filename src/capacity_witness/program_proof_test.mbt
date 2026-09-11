// Fixed proof and witness CIDs computed independently with Node crypto SHA-256.
// Object members are sorted before JSON.stringify; fixture claims are not facts.

///|
test "Program proof forms bind identities and retain repeated inputs" {
  let fixtures = [
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:1ab51a5f1486e13253054378a167d1c71840c08f8b8aa9aba3d3d3b3943cd5f0\"}",
      "sha256:1ab51a5f1486e13253054378a167d1c71840c08f8b8aa9aba3d3d3b3943cd5f0",
      2, false,
    ),
    (
      "{\"inputs\":[],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:ac2f5270372530381a80fda7a7d5a5f374e5dae82604058adda2fe969ec9b56b\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:ac2f5270372530381a80fda7a7d5a5f374e5dae82604058adda2fe969ec9b56b\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:f29874a0ccc16dcff3a379b4002226c157d45fa939162bc802e20abbccb06595\"}",
      "sha256:f29874a0ccc16dcff3a379b4002226c157d45fa939162bc802e20abbccb06595",
      0, false,
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000003\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000003\",\"sha256:1b015e8dff3a6a25da16df102346636d169ba3c321b4935dddc1e0abc1bb445d\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:1b015e8dff3a6a25da16df102346636d169ba3c321b4935dddc1e0abc1bb445d\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:124a7eb08e21dc7e5dc065ba7a851a6266ddbadb65e5b1a4317cbfbd31659365\"}",
      "sha256:124a7eb08e21dc7e5dc065ba7a851a6266ddbadb65e5b1a4317cbfbd31659365",
      2, true,
    ),
  ]
  for fixture in fixtures {
    let (proof, wire, expected, count, has_program) = fixture
    let limits : Limits = { max_bytes: 10000, max_nodes: 100, max_depth: 10, }
    let witness = admit(@utf8.encode(wire), expected, limits).unwrap()
    let bytes = @utf8.encode(proof)
    let claim = bind_program_proof(bytes, witness, limits).unwrap()
    let exact_nodes = (if has_program { 8 } else { 7 }) + count
    assert_true(
      bind_program_proof(bytes, witness, {
        ..limits,
        max_nodes: exact_nodes,
        max_depth: 2,
      })
      is Ok(_),
    )
    assert_true(
      bind_program_proof(bytes, witness, {
        ..limits,
        max_nodes: exact_nodes - 1,
      })
      is Err(BudgetExceeded),
    )
    assert_true(
      bind_program_proof(bytes, witness, { ..limits, max_depth: 1, })
      is Err(BudgetExceeded),
    )
    assert_eq(cid(program_proof_witness(claim)), expected)
    assert_eq(program_proof_input_count(claim), count)
    assert_eq(program_proof_input_at(claim, count), None)
    assert_eq(program_proof_input_at(claim, -1), None)
    if count > 0 {
      assert_eq(
        program_proof_input_at(claim, 0),
        program_proof_input_at(claim, 1),
      )
    }
    if has_program {
      assert_eq(
        program_proof_form(claim),
        ProgramDependencies(
          "sha256:0000000000000000000000000000000000000000000000000000000000000003",
        ),
      )
    } else {
      assert_eq(program_proof_form(claim), DerivedInputs)
    }
    assert_true(
      bind_program_proof(bytes, witness, {
        ..limits,
        max_bytes: bytes.length(),
      })
      is Ok(_),
    )
    assert_true(
      bind_program_proof(bytes, witness, {
        ..limits,
        max_bytes: bytes.length() - 1,
      })
      is Err(BudgetExceeded),
    )
    assert_true(
      bind_program_proof(bytes, witness, { ..limits, max_nodes: 0, })
      is Err(BudgetExceeded),
    )
    assert_true(
      bind_program_proof(bytes, witness, { ..limits, max_depth: 0, })
      is Err(BudgetExceeded),
    )
    assert_true(
      bind_program_proof(bytes, witness, { ..limits, max_bytes: -1, })
      is Err(InvalidLimits),
    )
  }
}

///|
test "Program proof binding rejects self-consistent foreign and noncanonical claims" {
  let fixtures : Array[(String, String, String, Issue)] = [
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/1.0\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:df539e8bea45e3f15759a74b92dbe42ca257b21036874b024fa8b8cd7feb776c\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:df539e8bea45e3f15759a74b92dbe42ca257b21036874b024fa8b8cd7feb776c\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:190b54b872ca9c430439999ebad8767f34cee409fd59c2b61d2d06ac74503ced\"}",
      "sha256:190b54b872ca9c430439999ebad8767f34cee409fd59c2b61d2d06ac74503ced",
      InvalidWitness,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:e97992e4766b48ecf0eeaba64dbc7a12d05687f7a256f36b852a1ef057abe13b\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:e97992e4766b48ecf0eeaba64dbc7a12d05687f7a256f36b852a1ef057abe13b\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:5dc264707a8decb91606ab4002fa48836b3e4e35dde074f5e646bd9026cd1154\"}",
      "sha256:5dc264707a8decb91606ab4002fa48836b3e4e35dde074f5e646bd9026cd1154",
      InvalidWitness,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"bytes\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:528c3c52a3345f1101c64b9b0d7b4b229a815b7c5e3a565ca281654b59d06aa0\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:528c3c52a3345f1101c64b9b0d7b4b229a815b7c5e3a565ca281654b59d06aa0\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:6b897bbf43d8a2da5ac7c6743e4bfc4e2260fef7a7faaf7938849e97982b90cf\"}",
      "sha256:6b897bbf43d8a2da5ac7c6743e4bfc4e2260fef7a7faaf7938849e97982b90cf",
      InvalidWitness,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.filter\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:a7baa46cb120c7a572bfe53de0f71341c0b246fce74e0b5ce70f1bb34f5c5932\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:a7baa46cb120c7a572bfe53de0f71341c0b246fce74e0b5ce70f1bb34f5c5932\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:282b38336f23216fc89472537f513715da3a585f483a53ea7010d5fc59d74ac6\"}",
      "sha256:282b38336f23216fc89472537f513715da3a585f483a53ea7010d5fc59d74ac6",
      InvalidWitness,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:1\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:b3f40df21b4a5409d02258a3ba0cd073df046f4ec248a1f854baa05278f11d7b\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:b3f40df21b4a5409d02258a3ba0cd073df046f4ec248a1f854baa05278f11d7b\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:c7ae1d34efc21ba8ef4d7fb7152ac8b067ac95eced20581211d5e48b2b6d99dc\"}",
      "sha256:c7ae1d34efc21ba8ef4d7fb7152ac8b067ac95eced20581211d5e48b2b6d99dc",
      InvalidWitness,
    ),
    (
      "{\"extra\":true,\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:b2e949af4db1de438963bd4335be97374cc02de77c07fe245e7edcf519d27118\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:b2e949af4db1de438963bd4335be97374cc02de77c07fe245e7edcf519d27118\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:632a2f407047d322b6d8eb3488b133d3e532e9f1ec739c9809b41d9516ee5bce\"}",
      "sha256:632a2f407047d322b6d8eb3488b133d3e532e9f1ec739c9809b41d9516ee5bce",
      InvalidWitness,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000002\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000002\",\"sha256:5e1ad72aa64aa0d1a556872911069b11aeb105cc630521108b8bbfbc534d6080\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:5e1ad72aa64aa0d1a556872911069b11aeb105cc630521108b8bbfbc534d6080\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:8372f34026f3c37b6ac156981f0928e8963f7a9e27b04497cdd868f49865d5b1\"}",
      "sha256:8372f34026f3c37b6ac156981f0928e8963f7a9e27b04497cdd868f49865d5b1",
      InvalidWitness,
    ),
    (
      "{\"inputs\":[\"not-a-cid\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:d3cc16a2f06e9c84d7de214f94c00be2df33a3cc99670cd4d6a9595e8c40b81d\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:d3cc16a2f06e9c84d7de214f94c00be2df33a3cc99670cd4d6a9595e8c40b81d\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:b7cb05838131939bfda76038de696554cd12eb73d67c518cdb3ba5e8822162e3\"}",
      "sha256:b7cb05838131939bfda76038de696554cd12eb73d67c518cdb3ba5e8822162e3",
      InvalidWitness,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000009\",\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:46cbb3f244cf6deb697a6df6c73fa87e5ecfade4e3a5b09a72796280681e0003\"}",
      "sha256:46cbb3f244cf6deb697a6df6c73fa87e5ecfade4e3a5b09a72796280681e0003",
      InvalidWitness,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:da1e1ad8b4f62ccde865a184b5c98eed18cdb6cfbcde1dfc1fb45b729212da8f\"}",
      "sha256:da1e1ad8b4f62ccde865a184b5c98eed18cdb6cfbcde1dfc1fb45b729212da8f",
      InvalidWitness,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000009\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000009\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:530fc2beed12ba02fb9bb18f62168313fabe12110aad95623b2ed9169475a42e\"}",
      "sha256:530fc2beed12ba02fb9bb18f62168313fabe12110aad95623b2ed9169475a42e",
      IdentityMismatch,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_artifact_rows\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:0a953f95514c88323a0a5962728e5d3cdeec139a9503b9cd93e35670cb48473c\"}",
      "sha256:0a953f95514c88323a0a5962728e5d3cdeec139a9503b9cd93e35670cb48473c",
      InvalidWitness,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\"],\"derivation\":{\"op\":\"enforced_ceiling\",\"resolved_limit_cid\":\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:8bdf2f69f99426c0c719b34e1bdc762f89e0f036cde8462f3cf49bb7f1ffd21e\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:65c0b2367a5fb6c5fca1bf17339a0d988cff6709f603bd12cff40f8d887fcb9a\"}",
      "sha256:65c0b2367a5fb6c5fca1bf17339a0d988cff6709f603bd12cff40f8d887fcb9a",
      InvalidWitness,
    ),
    (
      " {\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:cf570990b58ffda018f9b141c3d4cc51fc120510adc002f3299be7e19f255f0a\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:cf570990b58ffda018f9b141c3d4cc51fc120510adc002f3299be7e19f255f0a\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:49c963e42fda8c8cc556b38b5a4985059cb19c0fb6df3d01b906bfdc87b9d6fe\"}",
      "sha256:49c963e42fda8c8cc556b38b5a4985059cb19c0fb6df3d01b906bfdc87b9d6fe",
      NoncanonicalArtifact,
    ),
    (
      "{\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2.0,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:b78c0ac67b46f57ca1b680fe4aa76eafbda37be426b408e7ca9d9a56f26dc576\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:b78c0ac67b46f57ca1b680fe4aa76eafbda37be426b408e7ca9d9a56f26dc576\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:84ecf59ef6796b00ac32b30d80203ff0b5dca08b79032a6d929442d81d705759\"}",
      "sha256:84ecf59ef6796b00ac32b30d80203ff0b5dca08b79032a6d929442d81d705759",
      NoncanonicalArtifact,
    ),
    (
      "{\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0378b340989c3d6d983bf52b3133f891de5cde4cbe703da984079189e4cba94c\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0378b340989c3d6d983bf52b3133f891de5cde4cbe703da984079189e4cba94c\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:74d85ef9381c5611877af3d849bf4291081c96323dcb182ee2d950ecc941b454\"}",
      "sha256:74d85ef9381c5611877af3d849bf4291081c96323dcb182ee2d950ecc941b454",
      InvalidWitness,
    ),
    (
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"inputs\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000001\"],\"law_id\":\"actql.bound.append\",\"program_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000003\",\"semantic_ref\":\"step:0\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}",
      "{\"dependencies\":[\"sha256:0000000000000000000000000000000000000000000000000000000000000001\",\"sha256:0000000000000000000000000000000000000000000000000000000000000003\",\"sha256:d919506670d6d7c4cf29f3372a8862f61d7f69a41bd0ab5c4634b3ac0249aa7e\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:d919506670d6d7c4cf29f3372a8862f61d7f69a41bd0ab5c4634b3ac0249aa7e\",\"semantic_ref\":\"step:0\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:8e70e1eb838b67065b442714bba2ff07fd6ac67e3221229ecddaf8a97b254270\"}",
      "sha256:8e70e1eb838b67065b442714bba2ff07fd6ac67e3221229ecddaf8a97b254270",
      InvalidWitness,
    ),
  ]
  for fixture in fixtures {
    let (proof, wire, expected, issue) = fixture
    let limits : Limits = { max_bytes: 10000, max_nodes: 100, max_depth: 10, }
    let witness = admit(@utf8.encode(wire), expected, limits).unwrap()
    match bind_program_proof(@utf8.encode(proof), witness, limits) {
      Err(actual) => assert_eq(actual, issue)
      Ok(_) => fail("invalid proof accepted")
    }
  }
}
