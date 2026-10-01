///|
fn structural_limits(limits : CheckLimits) -> @aql.Limits {
  {
    frontend: {
      max_tokens: 100000,
      max_syntax_nodes: 100000,
      max_syntax_depth: 128,
      max_literal_bytes: 1000000,
      max_symbol_count: 10000,
      max_generated_steps: 10000,
      max_generated_fields: 100000,
      max_lowering_work: 10000000,
    },
    construction: {
      source: limits.input.source,
      tree: limits.input.tree,
      max_origin_entries: 100000,
      max_output_bytes: 1000000,
    },
    max_stages: limits.input.max_stages,
  }
}

///|
test "structural authored forward references reach the common checker with original locations" {
  let (_, _, environment, _, limits) = public_input_fixture(generated=true)
  let text =
    #|AQL '0.1'; PROGRAM 'forward' {
    #| STAGE s {
    #|  STEP {"from":"future","take":1,"as":"early"};
    #|  STEP {"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"future"};
    #|  RESULT r = {"from":"early"};
    #| }
    #| RESULT r = {"from":{"stage":"s","result":"r"}};
    #|}
  let parsed = @aql.parse_fixture(
    text,
    structural_limits(limits),
    source_path="forward.aql",
  ).unwrap()
  match
    check_parsed_with_evidence(
      @aql.program(parsed),
      environment,
      None,
      [],
      limits,
    ) {
    Rejected(diagnostic) => {
      let location = diagnostic_location(diagnostic).unwrap()
      assert_eq(diagnostic_location_source_path(location), "forward.aql")
      // Byte offsets refer to the authored STEP body, not emitted JSON.
      match diagnostic_location_position(location) {
        @source.Source(span) => {
          assert_eq(span.start_line, 3)
          assert_eq(span.start_column, 16)
          assert_eq(span.end_column, 24)
        }
        _ => fail("expected original byte location")
      }
    }
    _ => fail("the ordinary checker must reject a forward producer reference")
  }
}

///|
test "structural text retains common checker identities and evidence requirements" {
  for generated in [false, true] {
    let (_, ordinary, environment, evidence, limits) = public_input_fixture(
      generated~,
    )
    let text = @aql.format_fixture(
      ordinary,
      limits.input.source.max_input_bytes,
    ).unwrap()
    let parsed = @aql.parse_fixture(text, {
      frontend: {
        max_tokens: 100000,
        max_syntax_nodes: 100000,
        max_syntax_depth: 128,
        max_literal_bytes: 1000000,
        max_symbol_count: 10000,
        max_generated_steps: 10000,
        max_generated_fields: 100000,
        max_lowering_work: 10000000,
      },
      construction: {
        source: limits.input.source,
        tree: limits.input.tree,
        max_origin_entries: 100000,
        max_output_bytes: 1000000,
      },
      max_stages: limits.input.max_stages,
    }).unwrap()
    let a = public_checked(
      check_parsed_with_evidence(ordinary, environment, None, evidence, limits),
    )
    let b = public_checked(
      check_parsed_with_evidence(
        @aql.program(parsed),
        environment,
        None,
        evidence,
        limits,
      ),
    )
    assert_eq(unit_count(a), unit_count(b))
    for i in 0..<unit_count(a) {
      assert_eq(unit_definition_cid(a, i), unit_definition_cid(b, i))
      assert_eq(unit_contracts_cid(a, i), unit_contracts_cid(b, i))
      assert_eq(unit_used_values_cid(a, i), unit_used_values_cid(b, i))
    }
    match
      (
        check_parsed_with_evidence(ordinary, environment, None, [], limits),
        check_parsed_with_evidence(
          @aql.program(parsed),
          environment,
          None,
          [],
          limits,
        ),
      ) {
      (Checked(_), Checked(_)) => ()
      (Rejected(a), Rejected(b)) =>
        assert_eq(diagnostic_category(a), diagnostic_category(b))
      (NeedsInputs(a), NeedsInputs(b)) =>
        assert_eq(input_request_count(a), input_request_count(b))
      _ => fail("source spelling changed common admission requirements")
    }
  }
}
