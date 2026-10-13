///|
test "predicate diagnostics use only the original authored construction owner" {
  let (_, _, environment, _, limits) = public_input_fixture()
  let text =
    #|{"version":"actql/0.1","id":"p","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"filter":{"literal":1},"as":"out"}],"results":{"out":{"from":"out"}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let raw = @source.parse_json_measured(
    text,
    limits.input.source,
    source_path="predicate.actql",
  ).unwrap()
  let cursor = @decode.admit(raw.node, limits.input.tree).unwrap()
  let document = @origin.document(
    text,
    limits.input.source.max_input_bytes,
    source_path="predicate.actql",
  ).unwrap()
  for generated in [false, true] {
    let builder = @builder.create(document, {
      source: limits.input.source,
      tree: limits.input.tree,
      max_origin_entries: 1000,
      max_output_bytes: 10000,
    }).unwrap()
    let node = if generated {
      @builder.import_cursor(
        builder,
        cursor,
        @origin.range(document, 0, 0, kind=Generated).unwrap(),
      ).unwrap()
    } else {
      @builder.import_parsed(builder, raw).unwrap()
    }
    let source = @builder.finish(builder, node).unwrap()
    let program = @syntax.admit_generated_source(source, limits.input).unwrap()
    let diagnostic = public_rejected(
      @program_check.check_parsed(program, environment, None, limits),
    )
    assert_eq(@program_check.diagnostic_category(diagnostic), InvalidInput)
    guard @program_check.diagnostic_cause(diagnostic)
      is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
      fail("expected the unchanged common predicate classifier")
    }
    assert_eq(issue.kind, @pipeline.Operation(@relation.ExpectedBoolean))
    let origin = @program_check.diagnostic_predicate_origin(
      diagnostic, program, source,
    )
    let snapshot_origin = @program_check.diagnostic_predicate_origin_from_source(
      diagnostic, source,
    )
    if generated {
      assert_true(origin is None)
      assert_true(snapshot_origin is None)
    } else {
      let origin = origin.unwrap()
      assert_eq(@origin.kind(origin), Authored)
      assert_eq(
        (@origin.start(origin).byte_offset, @origin.end(origin).byte_offset),
        (177, 190),
      )
      let snapshot_origin = snapshot_origin.unwrap()
      assert_eq(@origin.kind(snapshot_origin), Authored)
      assert_eq(
        (
          @origin.start(snapshot_origin).byte_offset,
          @origin.end(snapshot_origin).byte_offset,
        ),
        (177, 190),
      )
    }
    // Equal source bytes, spans and paths cannot substitute for cursor identity.
    let other_builder = @builder.create(document, {
      source: limits.input.source,
      tree: limits.input.tree,
      max_origin_entries: 1000,
      max_output_bytes: 10000,
    }).unwrap()
    let other_source = @builder.finish(
      other_builder,
      @builder.import_parsed(other_builder, raw).unwrap(),
    ).unwrap()
    let other_program = @syntax.admit_generated_source(
      other_source,
      limits.input,
    ).unwrap()
    assert_true(
      @program_check.diagnostic_predicate_origin_from_source(
        diagnostic, other_source,
      )
      is None,
    )
    let other_diagnostic = public_rejected(
      @program_check.check_parsed(other_program, environment, None, limits),
    )
    assert_true(
      @program_check.diagnostic_predicate_origin_from_source(
        other_diagnostic, source,
      )
      is None,
    )
    assert_true(
      @program_check.diagnostic_predicate_origin(
        diagnostic, other_program, other_source,
      )
      is None,
    )
    assert_true(
      @program_check.diagnostic_predicate_origin(
        diagnostic, program, other_source,
      )
      is None,
    )
    assert_true(
      @program_check.diagnostic_predicate_origin(
        diagnostic, other_program, source,
      )
      is None,
    )
    let parsed = @syntax.parse(text, limits.input, format=Json).unwrap()
    assert_true(
      @program_check.diagnostic_predicate_origin(diagnostic, parsed, source)
      is None,
    )
  }
}
