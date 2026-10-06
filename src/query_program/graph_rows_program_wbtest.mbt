///|
test "Graph row module emits the existing Bridge without fabricated type facts" {
  let text = "FROM g |> node_rows() |> SELECT p, node_key"
  let query = @query.parse_query(text, mapping_syntax_limits()).unwrap()
  let mapping = @query.parse_graph(
    "PROPERTY GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p)))",
    mapping_syntax_limits(),
  ).unwrap()
  let input = property_input(
    "n",
    ["node_key", "p"],
    "{\"values\":{\"schema\":{\"node_key\":{\"type\":\"number\",\"nullable\":false},\"p\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[]},\"as\":\"n\"}",
  )
  let graph : ScriptGraph = {
    name: { value: "g", quoted: false, },
    producer: "g",
    mapping,
    inputs: [input],
  }
  assert_eq(script_graph_row_columns(graph, false), [
    "id", "labels", "node_key", "p",
  ])
  assert_true(script_has_graph_rows(query))
  let document = @origin.document(text, 10000).unwrap()
  let builder = @builder.create(document, mapping_limits().source).unwrap()
  let construction : Construction = {
    builder,
    generated: @origin.range(document, 0, 0, kind=Generated).unwrap(),
  }
  let steps = []
  let bound = lower_script_graph_rows(
    construction,
    query,
    graph,
    mapping_limits(),
    steps,
    [],
    "out",
  )
  assert_eq(bound.visible_fields, ["p", "node_key"])
  assert_eq(bound.name, "out")
  assert_true(bound.source is StepReference)
  let root = construction.array(steps)
  let source = @builder.finish(builder, root).unwrap()
  let cursor = @builder.cursor(source)
  assert_eq(@wire.array_length(cursor), Some(2))
  let bridge = @wire.open_object(@wire.element_at(cursor, 0).unwrap()).unwrap()
  assert_eq(@wire.text(@wire.lookup(bridge, "from").unwrap()), Ok("g"))
  assert_eq(@wire.boolean(@wire.lookup(bridge, "node_rows").unwrap()), Ok(true))
  assert_eq(
    @wire.object_field_names(@wire.element_at(cursor, 0).unwrap())
    .unwrap()
    .length(),
    3,
  )
}
