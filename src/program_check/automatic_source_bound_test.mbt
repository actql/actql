///|
test "global group derives its one-row bound rather than transferring an empty input" {
  let (text, _, environment, _, limits) = public_input_fixture(generated=true)
  let source = text
    .replace(old="\"rows\":[{\"id\":1}]", new="\"rows\":[]")
    .replace(
      old="{\"take\":1,\"as\":\"selected\"}",
      new="{\"group\":{\"by\":[],\"aggregates\":{}}},{\"derive\":{\"id\":\"1\",\"value\":\"1\"},\"as\":\"selected\"}",
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
  let input = @program_check.unit_publication_at(program, 0, 0).unwrap()
  let output = @program_check.unit_publication_at(program, 1, 0).unwrap()
  assert_eq(
    @context.publication_row_limit_maximum(
      @program_check.publication_selection(input),
    ),
    0L,
  )
  assert_eq(
    @context.publication_row_limit_maximum(
      @program_check.publication_selection(output),
    ),
    1L,
  )
  let proof = @program_check.publication_proof_at(output, 0).unwrap()
  assert_eq(@program_check.proof_source(proof).source_ordinal, 0)
  assert_eq(@program_check.proof_input_count(proof), 0)
}

///|
test "invalid bound selection counts stay diagnostics rather than requests or absent evidence" {
  let (text, _, environment, _, limits) = public_input_fixture()
  let source = text
    .replace(old="\"default\":1", new="\"default\":0")
    .replace(old="\"take\":1", new="\"take\":{\"$param\":\"n\"}")
  assert_true(
    @program_check.check_document(
      source,
      environment,
      None,
      limits,
      format=Json,
    )
    is Rejected(_),
  )
}
