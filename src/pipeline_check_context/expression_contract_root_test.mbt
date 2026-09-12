///|
test "each owned stage resolves its emitted expression root without a caller CID" {
  let (identity, _, _) = prepared_identity_fixture()
  let (other, _, _) = prepared_identity_fixture()
  assert_true(!physical_equal(identity, other))
  assert_eq(program_identity_stage_count(identity), 2)
  let original_usage = program_identity_usage(identity)
  for i in 0..<2 {
    let stage = program_identity_stage_at(identity, i).unwrap()
    let semantic = @program_refs.stage_definition_semantics(
      stage_identity_definition(stage),
    )
    let root = stage_identity_expression_contract_cid(stage)
    assert_eq(
      root, "sha256:399d4593f8212a2239a0a3e3ca552653ad711010a180207f967cf546012fc1cb",
    )
    assert_eq(root, @program_refs.stage_semantics_expression_contract(semantic))
    let inherited = stage_identity_inherited_text_time(stage).unwrap()
    let expression_body = stage_identity_expression_body(stage).unwrap()
    assert_eq(expression_body, @environment.ExpressionRoot)
    assert_eq(@environment.expression_contract_body_cid(expression_body), root)
    assert_eq(
      @environment.expression_contract_dependency_count(expression_body),
      3,
    )
    assert_eq(
      @environment.expression_contract_dependency_at(expression_body, 0).unwrap().target,
      @environment.Inherited(inherited),
    )
    assert_eq(inherited, @environment.Base)
    assert_eq(
      @environment.inherited_text_time_cid(inherited),
      "sha256:2d41f38bd3bf8217d9bc394b1ca2ed9dfe6695b0088cd6a489328dabdee61dcc",
    )
    assert_eq(@environment.inherited_text_time_dependency_count(inherited), 8)
    // Semantic contract sharing does not equate the owned stage or Program.
    let foreign = program_identity_stage_at(other, i).unwrap()
    assert_true(!physical_equal(stage, foreign))
    assert_eq(stage_identity_expression_contract_cid(foreign), root)
    assert_true(
      physical_equal(program_identity_stage_at(identity, i).unwrap(), stage),
    )
  }
  // Read-only indexed access neither repeats hashing nor allocates a new owner.
  assert_eq(program_identity_usage(identity), original_usage)
  for invalid in [-2147483648, -1, 2, 2147483647] {
    assert_true(program_identity_stage_at(identity, invalid) is None)
  }
}

///|
test "expression inheritance refuses an unrelated or altered contract root" {
  for
    cid in [
      "", "sha256:399d4593f8212a2239a0a3e3ca552653ad711010a180207f967cf546012fc1cc",
      "sha256:2d41f38bd3bf8217d9bc394b1ca2ed9dfe6695b0088cd6a489328dabdee61dcc",
    ] {
    assert_true(@environment.inherited_text_time_for_expression(cid) is None)
  }
}
