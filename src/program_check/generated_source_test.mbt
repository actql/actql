///|
test "bounded generated Program uses the same common checker and identities" {
  for generated in [false, true] {
    let (text, parsed, environment, evidence, limits) = public_input_fixture(
      generated~,
    )
    let document = @origin.document(
      text,
      limits.input.source.max_input_bytes,
      source_path="fixture.actql",
    ).unwrap()
    let builder = @builder.create(document, {
      source: limits.input.source,
      tree: limits.input.tree,
      max_origin_entries: 100000,
      max_output_bytes: 1000000,
    }).unwrap()
    let raw = @source.parse_json_measured(
      text,
      limits.input.source,
      source_path="fixture.actql",
    ).unwrap()
    let node = @builder.import_parsed(builder, raw).unwrap()
    let source = @builder.finish(builder, node).unwrap()
    let built = @syntax.admit_generated_source(source, limits.input).unwrap()
    let a = public_checked(
      @program_check.check_parsed_with_evidence(
        parsed,
        environment,
        None,
        evidence,
        limits,
      ),
    )
    let b = public_checked(
      @program_check.check_parsed_with_evidence(
        built,
        environment,
        None,
        evidence,
        limits,
      ),
    )
    assert_eq(@program_check.unit_count(a), @program_check.unit_count(b))
    for i in 0..<@program_check.unit_count(a) {
      assert_eq(
        @program_check.unit_definition_cid(a, i),
        @program_check.unit_definition_cid(b, i),
      )
      assert_eq(
        @program_check.unit_contracts_cid(a, i),
        @program_check.unit_contracts_cid(b, i),
      )
      assert_eq(
        @program_check.unit_used_values_cid(a, i),
        @program_check.unit_used_values_cid(b, i),
      )
    }
    // A valid source owner still cannot authorize missing current capacity.
    let none_a = @program_check.check_parsed_with_evidence(
      parsed,
      environment,
      None,
      [],
      limits,
    )
    let none_b = @program_check.check_parsed_with_evidence(
      built,
      environment,
      None,
      [],
      limits,
    )
    match (none_a, none_b) {
      (Checked(_), Checked(_)) => ()
      (Rejected(a), Rejected(b)) =>
        assert_eq(
          @program_check.diagnostic_category(a),
          @program_check.diagnostic_category(b),
        )
      (NeedsInputs(a), NeedsInputs(b)) =>
        assert_eq(
          @program_check.input_request_count(a),
          @program_check.input_request_count(b),
        )
      _ => fail("generated source changed common checker evidence requirements")
    }
  }
}
