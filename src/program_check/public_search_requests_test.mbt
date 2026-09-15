///|
test "search requests retain missing operand roles without treating output caps as input proof" {
  let (text, _, environment, evidence, limits) = public_input_fixture(
    temporal_join_step=Some(2),
  )
  for kind in ["asof_join", "interval_join"] {
    let body = if kind == "asof_join" {
      "\"by\":[],\"left_id\":\"id\",\"left_time\":\"id\",\"right_time\":\"id\",\"direction\":\"nearest\",\"tolerance\":1"
    } else {
      "\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"value\"}"
    }
    for
      (left, right) in [
        (false, false),
        (true, false),
        (false, true),
        (true, true),
      ] {
      let source = text
        .replace(
          old="{\"take\":1,\"as\":\"selected\"}",
          new="{" +
            (if right { "\"take\":3" } else { "\"select\":[\"id\",\"value\"]" }) +
            ",\"as\":\"right_rows\"},{\"from\":\"rows\"," +
            (if left { "\"take\":2" } else { "\"select\":[\"id\",\"value\"]" }) +
            "},{\"" +
            kind +
            "\":{\"with\":\"right_rows\",\"kind\":\"inner\"," +
            body +
            ",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}},\"as\":\"joined\"}",
        )
        .replace(old="\"from\":\"selected\"", new="\"from\":\"rows\"")
      let parsed = @syntax.parse(
        source,
        limits.input,
        format=Json,
        source_path="search.actql",
      ).unwrap()
      let outcome = @program_check.check_parsed_with_evidence(
        parsed,
        environment,
        None,
        evidence,
        limits,
      )
      if left && right {
        ignore(public_checked(outcome))
        continue
      }
      let requests = match outcome {
        NeedsInputs(v) => v
        Rejected(d) => raise @program_check.diagnostic_cause(d)
        Checked(_) => fail("output limit substituted for search input proofs")
      }
      let expected : Array[@program_check.SearchInputSide] = if left {
        [Right]
      } else if right {
        [Left]
      } else {
        [Left, Right]
      }
      assert_eq(@program_check.input_request_count(requests), expected.length())
      for i, side in expected {
        let request = @program_check.input_request_at(requests, i).unwrap()
        guard request.kind is TemporalSearchInputRows(cursor, actual) else {
          fail("wrong search request")
        }
        assert_eq(actual, side)
        assert_true(
          physical_equal(
            @program_check.input_request_source(request).unwrap(),
            cursor,
          ),
        )
        assert_eq(@program_check.input_request_origin(request), ProgramDocument)
      }
      assert_true(@program_check.input_request_at(requests, -1) is None)
      assert_true(
        @program_check.input_request_at(requests, expected.length()) is None,
      )
      assert_eq(
        @program_check.diagnostic_location_source_path(
          @program_check.diagnostic_location(
            @program_check.input_requests_diagnostic(requests),
          ).unwrap(),
        ),
        "search.actql",
      )
      assert_true(
        @program_check.check_parsed_with_evidence(
          parsed,
          environment,
          None,
          evidence,
          { ..limits, compilation: { ..limits.compilation, work: 0, }, },
        )
        is Rejected(_),
      )
    }
  }
}
