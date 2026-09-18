///|
test "Result Definition seals the registered canonical preimage" {
  let program = "sha256:" + "1".repeat(64)
  let definition = prepare_result_definition(program, "first").unwrap()
  assert_eq(result_definition_program_cid(definition), program)
  assert_eq(result_definition_name(definition), "first")
  assert_eq(
    result_definition_cid(definition),
    "sha256:33cc81bf0c5e877d80d3dacf71d80fb8ef5472d6e224c83efac057853e67d966",
  )
  assert_eq(
    result_definition_json(definition).unwrap(),
    "{\"program_definition_cid\":\"" +
    program +
    "\",\"result_definition_cid\":\"sha256:33cc81bf0c5e877d80d3dacf71d80fb8ef5472d6e224c83efac057853e67d966\",\"result_name\":\"first\",\"version\":\"actql-result-definition/0.1\"}",
  )
}

///|
test "Result aliases and Unicode names retain exact identities" {
  let program = "sha256:" + "1".repeat(64)
  assert_eq(
    result_definition_cid(prepare_result_definition(program, "second").unwrap()),
    "sha256:e11eba03bcf3d0704ba0f54930d687a118b5a14875f160a46ccc189e142b2ae2",
  )
  assert_eq(
    result_definition_cid(
      prepare_result_definition(program, "résultat").unwrap(),
    ),
    "sha256:8fe2773635f96a4c49e6fb8e50c0a98693d475f331ddaf627b33e6c750208f56",
  )
}

///|
test "Result Definition rejects caller-shaped or noncanonical identity" {
  let program = "sha256:" + "1".repeat(64)
  assert_true(
    prepare_result_definition("sha256:" + "A".repeat(64), "result")
    is Err(InvalidProgramDefinitionCid),
  )
  assert_true(prepare_result_definition(program, "") is Err(EmptyResultName))
  assert_true(
    prepare_result_definition(program, "re\u{301}sultat")
    is Err(NonCanonicalResultName),
  )
}
