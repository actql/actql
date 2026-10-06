///|
test "unified source lowers Graph to the ordinary keyed Program" {
  let source = "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id"
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let result = lower(source, Text, Some(context)).unwrap()
  assert_true(result.document.contains("\"graph\""))
  assert_true(result.document.contains("\"match_nodes\""))
  assert_true(!result.document.contains("\"graph\":{\"nodes\""))
  assert_true(lower(source, Sql, Some(context)) is Err(WrongQueryForm))
}

///|
test "unified dependency checkpoint keeps logical Relation DATA and explicit Results" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let source = "DATA n = SELECT 2 AS id; FROM n |> RESULT original |> WHERE id > 0 |> RESULT active"
  let result = lower(source, Text, Some(context)).unwrap()
  assert_true(result.document.contains("\"original\""))
  assert_true(result.document.contains("\"active\""))
  assert_true(!result.document.contains("\"graph\""))
  assert_true(!result.document.contains("\"connector\""))
}

///|
test "unified dependency checkpoint preserves the public query parser" {
  let source = "SELECT id FROM records"
  assert_true(parse_query(source, Sql) is Ok(_))
  assert_true(parse_query(source, Text) is Ok(_))
  assert_true(parse_query(source, Json) is Err(InvalidFormat))
}

///|
test "unified dependency checkpoint has no retired constructor fallback" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  for
    source in [
      "DATA g = graph(nodes: n); FROM GRAPH g |> MATCH WALK (a) |> SELECT a.id",
      "DATA g = OP graph {}; FROM GRAPH g |> MATCH WALK (a) |> SELECT a.id",
    ] {
    assert_true(lower(source, Text, Some(context)) is Err(QuerySyntax(_)))
  }
}

///|
fn unified_graph_prefix() -> String {
  "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); "
}

///|
test "unified Graph equality DATA lowers to its independent complete Program" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let source = unified_graph_prefix() +
    "DATA same = FROM g |> graphs_equal(with: g); FROM same |> SELECT equal"
  let actual = lower(source, Text, Some(context), source_path="equality.aql").unwrap()
  // Independently authored from the current Graph equality contract and DATA
  // naming rules, not from serialized lowerer output or legacy SGA dispatch.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"frontend.route","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":1}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_0"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"aql_data_0","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"id","to":"id"}]}}]}],"edges":[]},"as":"aql_data_2"},{"from":"aql_data_2","graphs_equal":{"with":"aql_data_2"},"as":"aql_sga_4"},{"from":"aql_sga_4","select":["equal"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["equal"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    {
      source: { max_input_bytes: 65536, max_nodes: 8192, max_depth: 64, },
      tree: {
        max_nodes: 8192,
        max_depth: 64,
        max_string_bytes: 65536,
        max_total_string_bytes: 65536,
      },
      max_stages: 32,
    },
    format=Json,
  ).unwrap()
  assert_eq(actual.format, @program.Json)
  let writer = @encode.writer(65536, 8192, 64)
  @program.emit_program_source(expected, writer)
  assert_eq(actual.document, @encode.finish(writer))
  let program = actual.program.unwrap()
  assert_eq(@program.stage_count(program), 1)
  assert_eq(@program.export_count(program), 1)
  let steps = @wire.elements(
    lookup(@program.stage_body(@program.stages(program)[0]), "steps"),
  ).unwrap()
  assert_eq(steps.length(), 6)
  let equality = lookup(steps[4], "graphs_equal")
  assert_eq(@wire.text(lookup(equality, "with")).unwrap(), "aql_data_2")
  // The retained Program keeps the authored call coordinates, not positions
  // in the generated JSON. These fixed ASCII offsets identify the whole call.
  let span = @wire.cursor_span(equality)
  assert_eq(span.source_path, "equality.aql")
  assert_eq(span.start_byte, 131)
  assert_eq(span.end_byte, 152)
}

///|
test "unified Graph equality rejects malformed producer syntax at exact authored locations" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  for
    (call, reason, byte_offset) in [
      ("graphs_equal(with: 'g')", "Expected identifier", 150),
      ("graphs_equal(with: g, with: g)", "Duplicate SGA argument", 153),
    ] {
    let source = unified_graph_prefix() +
      "DATA same = FROM g |> " +
      call +
      "; FROM same |> SELECT equal"
    guard lower(source, Text, Some(context), source_path="invalid-equality.aql")
      is Err(QuerySyntax(diagnostic)) else {
      fail("malformed equality producer syntax must be rejected")
    }
    guard diagnostic.issue is @syntax.Syntax(actual) else {
      fail("equality rejection must retain the syntax reason")
    }
    assert_eq(actual, reason)
    let span = diagnostic.span.unwrap()
    assert_eq(span.source_path, "invalid-equality.aql")
    assert_eq(span.start_byte, byte_offset)
    assert_eq(span.end_byte, byte_offset)
    assert_eq(span.start_line, 1)
    assert_eq(span.end_line, 1)
    assert_eq(span.start_column, byte_offset + 1)
    assert_eq(span.end_column, byte_offset + 1)
  }
}

///|
test "unified Graph equality retains unresolved producer and invalid argument reasons" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let cases = [
    ("graphs_equal(with: missing)", true),
    ("graphs_equal(with: n)", true),
    ("graphs_equal()", false),
    ("graphs_equal(with: g, extra: true)", false),
  ]
  for (call, unknown_producer) in cases {
    let source = unified_graph_prefix() +
      "DATA same = FROM g |> " +
      call +
      "; FROM same |> SELECT equal"
    guard lower(source, Text, Some(context)) is Err(QueryLowering(actual)) else {
      fail("invalid equality arguments must retain a lowerer rejection")
    }
    assert_true(
      if unknown_producer {
        actual is @query.UnknownRelation
      } else {
        actual is @query.UnsupportedGraph
      },
      msg=call,
    )
    // These lowerer issues carry no location; do not fabricate a column span.
    assert_true(unknown_column_origin(QueryLowering(actual)) is None)
  }
}

///|
test "unified dependency refuses unsupported mean Graph source without legacy dispatch" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let source = unified_graph_prefix() +
    "DATA combined = mean_graphs(with: [g, g]); FROM GRAPH combined |> MATCH WALK (a:Node) |> SELECT a.id"
  assert_true(
    lower(source, Text, Some(context))
    is Err(QueryLowering(@query.UnsupportedGraph)),
  )
}
