///|
fn graph_diagnostic_source(
  text : String,
) -> (@check.CheckDiagnostic, @builder.Source) raise {
  let query = @syntax.parse_query(text, syntax_limits()).unwrap()
  guard @query.compile_with_source(query, context(), construction_limits())
    is Err(BindingPreparationSource(LocalProgram(issue), source)) else {
    fail("expected the original Graph refusal and its own immutable snapshot")
  }
  (
    @check.source_context_diagnostic(
      @context.local_program_diagnostic_issue(issue),
    ),
    source,
  )
}

///|
test "public Graph origin accessor retains all independent argument vectors" {
  for
    (text, start, end) in [
      (
        "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'invented') |> SELECT component_size",
        137, 147,
      ),
      (
        "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'weak', max_output_rows: 0) |> SELECT component_size",
        162, 163,
      ),
      (
        "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key",
        136, 139,
      ),
      (
        "/*😀*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'invented') |> SELECT component_size",
        147, 157,
      ),
      (
        "/*😀*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'weak', max_output_rows: 0) |> SELECT component_size",
        172, 173,
      ),
      (
        "/*😀*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key",
        146, 149,
      ),
      (
        "/*é*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'invented') |> SELECT component_size",
        146, 156,
      ),
      (
        "/*é*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'weak', max_output_rows: 0) |> SELECT component_size",
        171, 172,
      ),
      (
        "/*é*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key",
        145, 148,
      ),
      (
        "/* 'invented' 0 [1] */\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'invented') |> SELECT component_size",
        161, 171,
      ),
      (
        "/* 'invented' 0 [1] */\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'weak', max_output_rows: 0) |> SELECT component_size",
        186, 187,
      ),
      (
        "/* 'invented' 0 [1] */\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key",
        160, 163,
      ),
      (
        "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) , first AS (FROM g |> components(kind: 'weak') |> SELECT component_size), second AS (FROM g |> components(kind: 'invented') |> SELECT component_size) FROM second |> SELECT component_size",
        222, 232,
      ),
      (
        "/*😀*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) , first AS (FROM g |> components(kind: 'weak') |> SELECT component_size), second AS (FROM g |> components(kind: 'invented') |> SELECT component_size) FROM second |> SELECT component_size",
        232, 242,
      ),
      (
        "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: {ids: []}) |> node_rows() |> SELECT node_key",
        136, 145,
      ),
      (
        "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: {ids: [], unknown: true}) |> node_rows() |> SELECT node_key",
        136, 160,
      ),
    ] {
    let (diagnostic, source) = graph_diagnostic_source(text)
    let origin = @check.diagnostic_graph_argument_origin_from_source(
      diagnostic, source,
    ).unwrap()
    let admitted = @program.admit_generated_source(
      source,
      construction_limits().program,
    ).unwrap()
    assert_true(
      @check.diagnostic_graph_argument_origin(diagnostic, admitted, source)
      is Some(_),
    )
    assert_eq(@origin.kind(origin), Authored)
    assert_eq(
      (@origin.start(origin).byte_offset, @origin.end(origin).byte_offset),
      (start, end),
    )
    assert_true(
      @check.diagnostic_predicate_origin_from_source(diagnostic, source) is None,
    )
    let (foreign_diagnostic, foreign_source) = graph_diagnostic_source(text)
    let foreign_program = @program.admit_generated_source(
      foreign_source,
      construction_limits().program,
    ).unwrap()
    assert_true(
      @check.diagnostic_graph_argument_origin(
        diagnostic, foreign_program, source,
      )
      is None,
    )
    assert_true(
      @check.diagnostic_graph_argument_origin(
        diagnostic, admitted, foreign_source,
      )
      is None,
    )
    assert_true(
      @check.diagnostic_graph_argument_origin_from_source(
        diagnostic, foreign_source,
      )
      is None,
    )
    assert_true(
      @check.diagnostic_graph_argument_origin_from_source(
        foreign_diagnostic, source,
      )
      is None,
    )
  }
}

///|
test "Graph origin accessor refuses generated construction after the same checker" {
  for
    (text, expected) in [
      (
        "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'invented') |> SELECT component_size",
        @pipeline.Graph(InvalidBody),
      ),
      (
        "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key",
        @pipeline.InvalidBody,
      ),
      (
        "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: {ids: []}) |> node_rows() |> SELECT node_key",
        @pipeline.GraphMatch(Structure(InvalidBody)),
      ),
    ] {
    let (original, source) = graph_diagnostic_source(text)
    let query = @syntax.parse_query(text, syntax_limits()).unwrap()
    let document = @syntax.query_document(query)
    let builder = @builder.create(document, construction_limits().source).unwrap()
    let generated = @builder.finish(
      builder,
      @builder.import_cursor(
        builder,
        @builder.cursor(source),
        @origin.range(document, 0, 0, kind=Generated).unwrap(),
      ).unwrap(),
    ).unwrap()
    let prefix = @program.admit_generated_source(
      generated,
      construction_limits().program,
    ).unwrap()
    let parameters = @parameters.prepare(prefix, {
      max_parameters: 10000,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    }).unwrap()
    guard @results.check_local_program(parameters, {
        max_stages: 20,
        max_steps: 10000,
        max_results: 10000,
        max_work: 10000,
        max_text_bytes: 100000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
      })
      is Err(Pipeline(_, issue) as failure) else {
      fail("generated copy must retain the actual checker refusal")
    }
    assert_eq(issue.kind, expected)
    let diagnostic = @check.source_context_diagnostic(
      @context.local_program_diagnostic_issue(failure),
    )
    assert_true(
      @check.diagnostic_graph_argument_origin_from_source(diagnostic, generated)
      is None,
    )
    assert_true(
      @check.diagnostic_graph_argument_origin_from_source(original, generated)
      is None,
    )
    assert_true(
      @check.diagnostic_graph_argument_origin_from_source(diagnostic, source)
      is None,
    )
  }
}

///|
test "Graph projection does not adopt a predicate refusal" {
  let query = @syntax.parse_query(
    "WITH unused AS (SELECT 1 AS n WHERE 42) SELECT 1 AS n",
    syntax_limits(),
  ).unwrap()
  guard @query.compile_with_source(query, context(), construction_limits())
    is Err(BindingPreparationSource(LocalProgram(issue), source)) else {
    fail("expected the existing predicate error envelope")
  }
  let diagnostic = @check.source_context_diagnostic(
    @context.local_program_diagnostic_issue(issue),
  )
  assert_true(
    @check.diagnostic_predicate_origin_from_source(diagnostic, source)
    is Some(_),
  )
  assert_true(
    @check.diagnostic_graph_argument_origin_from_source(diagnostic, source)
    is None,
  )
}
