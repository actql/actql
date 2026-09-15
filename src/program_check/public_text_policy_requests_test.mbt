///|
test "required missing text policy exposes the exact partial request frontier" {
  let (text, _, environment, _, limits) = public_input_fixture()
  for
    expression in [
      "regex_match(NULL, 'a')", "parse_timestamp(NULL, 'yyyy')", "nfkc(NULL)",
    ] {
    let text = text.replace(old="id + $n", new=expression)
    let program = @syntax.parse(text, limits.input, format=Json).unwrap()
    guard @program_check.check_parsed(program, environment, None, limits)
      is NeedsInputs(requests) else {
      fail("missing text policy must be supplementable")
    }
    assert_eq(@program_check.input_request_count(requests), 1)
    let request = @program_check.input_request_at(requests, 0).unwrap()
    assert_true(request.kind is HostTextTimePolicy)
    assert_true(physical_equal(request.program, program))
    assert_true(physical_equal(request.environment, environment))
    assert_eq(@program_check.input_request_origin(request), CheckEnvironment)
    assert_eq(@program_check.input_request_path(request), [
      @source.Key("host_policy_profile"),
      @source.Key("text_time_evaluation"),
    ])
    assert_true(@program_check.input_request_source(request) is None)
    assert_true(@program_check.input_request_at(requests, -1) is None)
    assert_true(@program_check.input_request_at(requests, 1) is None)
    let cause = @program_check.diagnostic_cause(
      @program_check.input_requests_diagnostic(requests),
    )
    assert_true(
      match cause {
        Source(Checks(Patterns(Timestamp(MissingPolicy(_)))))
        | Source(Checks(Patterns(Regex(MissingPolicy(_)))))
        | Source(Checks(TextBounds(MissingPolicy(_)))) => true
        _ => false
      },
    )
    assert_true(
      @program_check.check_document(
        text,
        environment,
        None,
        limits,
        format=Json,
      )
      is NeedsInputs(_),
    )
    assert_true(
      @program_check.check_parsed(program, environment, None, {
        ..limits,
        compilation: { ..limits.compilation, work: 0, },
      })
      is Rejected(_),
    )
  }
}

///|
test "text policy supplementation rechecks admission and remaining profile obligations" {
  let good = "{\"max_input_codepoints\":1000,\"max_input_utf8_bytes\":1000,\"max_output_bytes\":1000,\"max_pattern_bytes\":1000,\"max_replacements\":1000,\"version\":\"actql-text-time-host-policy/0.1\"}"
  let (text, _, complete, _, limits) = public_input_fixture(
    text_policy=Some(
      (
        good, "sha256:6c6153b3d61d6d3dfd47f3055c7e2e1c16629c1a6868732ce11b975e31c9babf",
      ),
    ),
  )
  let text = text.replace(old="id + $n", new="regex_match(NULL, 'a')")
  // The earlier missing-policy frontier did not validate the unused declaration.
  guard @program_check.check_document(text, complete, None, limits, format=Json)
    is Rejected(later) else {
    fail("unused Parameter must still be checked")
  }
  assert_true(
    @program_check.diagnostic_cause(later)
    is @program_check.LocalConstructionFailure::Source(
      Identity(References(Usage(UnusedParameter(_))))
    ),
  )
  let text = text.replace(
    old="\"params\":{\"n\":{\"type\":\"number\",\"default\":1}},",
    new="",
  )
  assert_true(
    @program_check.check_document(text, complete, None, limits, format=Json)
    is Checked(_),
  )
  let (_, _, unsupported, _, _) = public_input_fixture(
    text_policy=Some(
      (
        good, "sha256:6c6153b3d61d6d3dfd47f3055c7e2e1c16629c1a6868732ce11b975e31c9babf",
      ),
    ),
    text_profile=false,
  )
  guard @program_check.check_document(
      text,
      unsupported,
      None,
      limits,
      format=Json,
    )
    is Rejected(profile_failure) else {
    fail("unsupported profile became a request")
  }
  assert_true(
    @program_check.diagnostic_cause(profile_failure)
    is @program_check.LocalConstructionFailure::Source(
      Checks(ExpressionProfiles(UnsupportedProfile(_, _)))
    ),
  )
  assert_true(
    @program_check.check_document(
      text.replace(old="regex_match(NULL, 'a')", new="regex_match(NULL, '(')"),
      complete,
      None,
      limits,
      format=Json,
    )
    is Rejected(_),
  )
  for
    (body, cid) in [
      (
        "null", "sha256:ef0f2156de47bf592c8cd1bcf5aa2fb4dfa443fb98296acd4e6db00c32b3d0cb",
      ),
      (
        "{}", "sha256:505a3a83ee6746d3483a07042071c422a4dfe19c3b8e9fcc6fb539bf57ed5f3a",
      ),
      (
        good.replace(
          old="\"max_pattern_bytes\":1000",
          new="\"max_pattern_bytes\":0",
        ),
        "sha256:d02e27a2b4399c0757090e81d9fb8bdfef071f1d0c0a3faf1345ee7833721e44",
      ),
    ] {
    let (_, _, invalid, _, _) = public_input_fixture(
      text_policy=Some((body, cid)),
    )
    guard @program_check.check_document(
        text,
        invalid,
        None,
        limits,
        format=Json,
      )
      is Rejected(diagnostic) else {
      fail("present invalid policy must not become a supplementation request")
    }
    assert_true(
      @program_check.diagnostic_cause(diagnostic)
      is @program_check.LocalConstructionFailure::Source(
        Checks(Validation(TextTime(_)))
      ),
    )
  }
}
