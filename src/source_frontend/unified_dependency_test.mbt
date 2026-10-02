///|
test "unified dependency checkpoint refuses Property Graph before common admission" {
  let source = "DATA n = SELECT 1 AS id; DATA g = PROPERTY GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node PROPERTIES (id))); FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.id"
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  assert_true(
    lower(source, Text, Some(context))
    is Err(QueryLowering(@query.UnsupportedGraph)),
  )
  assert_true(lower(source, Sql, Some(context)) is Err(WrongQueryForm))
}

///|
test "unified dependency checkpoint keeps logical Relation DATA and explicit Results" {
  let context = { ..test_context(), inputs: [], captured_stage: None, }
  let source = "DATA n = SELECT 2 AS id; FROM n |> RESULT original |> WHERE id > 0 |> RESULT active"
  let result = lower(source, Text, Some(context)).unwrap()
  assert_true(result.document.contains("\"original\""))
  assert_true(result.document.contains("\"active\""))
  assert_true(!result.document.contains("\"property_graph\""))
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
      "DATA g = OP graph {}; FROM GRAPH g |> MATCH WALK (a) |> SELECT a.id", "DATA same = FROM g |> graphs_equal(with: g);",
    ] {
    assert_true(lower(source, Text, Some(context)) is Err(QuerySyntax(_)))
  }
}
