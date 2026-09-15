///|
fn lexical_request_program(text : String) -> String {
  text
  .replace(
    old="{\"derive\":{\"value\":\"id + $n\"},\"as\":\"derived\"}",
    new="{\"derive\":{\"value\":\"id + $n\",\"text\":\"'a'\"},\"as\":\"docs\"},{\"text_rank\":{\"queries\":\"docs\",\"candidate_id\":\"id\",\"candidate_text\":\"text\",\"query_id\":\"id\",\"query_text\":\"text\",\"tokenizer\":\"unicode_words\",\"scoring\":{\"bm25\":{\"k1\":1.2,\"b\":0.75}},\"k\":1}},{\"select\":[{\"id\":\"candidate_id\"},{\"value\":\"query_id\"}],\"as\":\"derived\"}",
  )
  .replace(old="\"candidate_id\":\"id\"", new="\"candidate_id\":\"text\"")
  .replace(old="\"query_id\":\"id\"", new="\"query_id\":\"text\"")
}

///|
test "lexical selection and admitted artifact are separate input requests" {
  let (text, _, absent, _, limits) = public_input_fixture(lexical_profile=true)
  let text = lexical_request_program(text)
  let program = @syntax.parse(text, limits.input, format=Json).unwrap()
  guard @program_check.check_parsed(program, absent, None, limits)
    is NeedsInputs(selection) else {
    fail("expected lexical selection request")
  }
  let request = @program_check.input_request_at(selection, 0).unwrap()
  assert_true(request.kind is HostTextRankSelection)
  assert_true(@program_check.input_request_source(request) is None)
  assert_eq(@program_check.input_request_path(request), [
    @source.Key("host_policy_profile"),
    @source.Key("text_rank"),
  ])
  let pin = "sha256:b75e7a20e9da2007253d6f47aa19e9d64024f9d9fa2a21cc915d46712689acd2"
  let body = "{\"profile_bytes_cid\":\"" +
    pin +
    "\",\"version\":\"actql-text-rank-selection/0.1\"}"
  let (_, _, selected, _, _) = public_input_fixture(
    lexical_profile=true,
    lexical_selection=Some(
      (
        body, "sha256:94600a40d32100a52a629ed772d99c3ae1ff2bd5d166d4e9ad18219502c888b2",
      ),
    ),
  )
  guard @program_check.check_parsed(program, selected, None, limits)
    is NeedsInputs(artifacts) else {
    fail("selected pin is not an admitted profile")
  }
  assert_eq(@program_check.input_request_count(artifacts), 1)
  let artifact = @program_check.input_request_at(artifacts, 0).unwrap()
  guard artifact.kind is TextRankProfileArtifact(retained) else {
    fail("artifact request")
  }
  assert_eq(@environment.text_rank_selection_cid(retained), pin)
  guard @program_check.diagnostic_cause(
      @program_check.input_requests_diagnostic(artifacts),
    )
    is @program_check.LocalConstructionFailure::Closure(
      Operations(Lexical(MissingArtifact(original)))
    ) else {
    fail("artifact diagnostic lost its selection")
  }
  assert_true(physical_equal(retained, original))
  assert_true(
    @environment.admit_text_rank_profile(retained, @utf8.encode("{}"), [], {
      max_profile_bytes: 10000,
      max_dependency_bytes: 10000,
      max_nodes: 1000,
      max_depth: 10,
    })
    is Err(_),
  )
  assert_true(physical_equal(artifact.program, program))
  assert_true(physical_equal(artifact.environment, selected))
  assert_eq(@program_check.input_request_origin(artifact), CheckEnvironment)
  assert_eq(@program_check.input_request_path(artifact), [
    @source.Key("host_policy_profile"),
    @source.Key("text_rank"),
    @source.Key("profile_bytes_cid"),
  ])
  let source = @program_check.input_request_source(artifact).unwrap()
  assert_eq(@decode.text(source), Ok(pin))
  assert_true(
    physical_equal(
      source,
      @program_check.input_request_source(artifact).unwrap(),
    ),
  )
  assert_true(@program_check.input_request_at(artifacts, -1) is None)
  assert_true(@program_check.input_request_at(artifacts, 1) is None)
  assert_true(
    @program_check.check_document(text, selected, None, limits, format=Json)
    is NeedsInputs(_),
  )
  // Original immutable frontier still describes the absent selection.
  assert_true(
    @program_check.input_request_at(selection, 0).unwrap().kind
    is HostTextRankSelection,
  )
  for
    (bad, cid) in [
      (
        "null", "sha256:1256f2f148915ac362dca90e05809e37ab62493b248b802357a9d17f76c19af7",
      ),
      (
        "{}", "sha256:0b1e12e9f077f19c84cd4292f31f378e8e1b3e4b2ad147b543b3cd9825da3642",
      ),
    ] {
    let (_, _, invalid, _, _) = public_input_fixture(
      lexical_profile=true,
      lexical_selection=Some((bad, cid)),
    )
    guard @program_check.check_parsed(program, invalid, None, limits)
      is Rejected(diagnostic) else {
      fail("malformed selection became a request")
    }
    assert_true(
      @program_check.diagnostic_cause(diagnostic)
      is @program_check.LocalConstructionFailure::Closure(
        Operations(Lexical(Selection(InvalidComponent)))
      ),
    )
  }
  assert_true(
    @program_check.check_parsed(program, selected, None, {
      ..limits,
      compilation: { ..limits.compilation, work: 0, },
    })
    is Rejected(_),
  )
}
