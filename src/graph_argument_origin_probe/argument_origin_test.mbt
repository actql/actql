///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: components-kind-plain" {
  let source = "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'invented') |> SELECT component_size"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = Graph(InvalidBody)
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (137, 147))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: components-max-output-rows-plain" {
  let source = "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'weak', max_output_rows: 0) |> SELECT component_size"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = Graph(InvalidCount)
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (162, 163))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: subgraph-nodes-plain" {
  let source = "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = InvalidBody
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (136, 139))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: components-kind-emoji-crlf" {
  let source = "/*😀*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'invented') |> SELECT component_size"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = Graph(InvalidBody)
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (147, 157))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: components-max-output-rows-emoji-crlf" {
  let source = "/*😀*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'weak', max_output_rows: 0) |> SELECT component_size"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = Graph(InvalidCount)
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (172, 173))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: subgraph-nodes-emoji-crlf" {
  let source = "/*😀*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = InvalidBody
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (146, 149))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: components-kind-decomposed-crlf" {
  let source = "/*é*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'invented') |> SELECT component_size"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = Graph(InvalidBody)
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (146, 156))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: components-max-output-rows-decomposed-crlf" {
  let source = "/*é*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'weak', max_output_rows: 0) |> SELECT component_size"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = Graph(InvalidCount)
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (171, 172))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: subgraph-nodes-decomposed-crlf" {
  let source = "/*é*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = InvalidBody
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (145, 148))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: components-kind-decoy-comment" {
  let source = "/* 'invented' 0 [1] */\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'invented') |> SELECT component_size"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = Graph(InvalidBody)
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (161, 171))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: components-max-output-rows-decoy-comment" {
  let source = "/* 'invented' 0 [1] */\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'weak', max_output_rows: 0) |> SELECT component_size"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = Graph(InvalidCount)
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (186, 187))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: subgraph-nodes-decoy-comment" {
  let source = "/* 'invented' 0 [1] */\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> subgraph(nodes: [1]) |> node_rows() |> SELECT node_key"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = InvalidBody
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (160, 163))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: components-kind-repeated-plain" {
  let source = "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) , first AS (FROM g |> components(kind: 'weak') |> SELECT component_size), second AS (FROM g |> components(kind: 'invented') |> SELECT component_size) FROM second |> SELECT component_size"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = Graph(InvalidBody)
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (222, 232))
}

///|
// Expected byte coordinates are independently authored literal-input facts.
test "required exact Graph argument origin: components-kind-repeated-emoji-crlf" {
  let source = "/*😀*/\r\nWITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) , first AS (FROM g |> components(kind: 'weak') |> SELECT component_size), second AS (FROM g |> components(kind: 'invented') |> SELECT component_size) FROM second |> SELECT component_size"
  let actual = @query.compile_query_script(
    @syntax.parse_query_script(source, syntax_limits()).unwrap(),
    context(),
    construction_limits(),
  )
  guard actual is Err(BindingPreparation(LocalProgram(Pipeline(stage, issue)))) else {
    fail("expected the original common Graph argument refusal")
  }
  let expected : @pipeline.IssueKind = Graph(InvalidBody)
  assert_eq(stage, 0)
  assert_eq(issue.kind, expected)
  assert_eq((issue.span.start_byte, issue.span.end_byte), (232, 242))
}

///|
test "valid source-free components control: weak" {
  let source = "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'weak', max_output_rows: 1) |> SELECT component_size"
  assert_true(
    @query.compile_query_script(
      @syntax.parse_query_script(source, syntax_limits()).unwrap(),
      context(),
      construction_limits(),
    )
    is Ok(_),
  )
}

///|
test "valid source-free components control: strong" {
  let source = "WITH n AS (SELECT 1 AS node_key), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) FROM g |> components(kind: 'strong', max_output_rows: 1) |> SELECT component_size"
  assert_true(
    @query.compile_query_script(
      @syntax.parse_query_script(source, syntax_limits()).unwrap(),
      context(),
      construction_limits(),
    )
    is Ok(_),
  )
}
