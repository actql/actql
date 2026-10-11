///|
// Seed admitted lexical coordinates independently of parser-generated names.
// These controls exercise reference roles, not Carrier admission or execution.
fn producer_scope_parser(text : String) -> QueryParser {
  let source = tokenize(
    text,
    query_limits().lexical,
    source_path="producer-scope.sql",
  ).unwrap()
  {
    source,
    limits: query_limits(),
    index: 0,
    work: 0,
    expression_nodes: 0,
    syntax_nodes: 0,
    source_depth: 0,
    synthetic_sources: 0,
    cte_scopes: [
      [
        (
          { value: "rows", quoted: false, },
          { value: "outer_rows", quoted: false, },
        ),
        (
          { value: "peer", quoted: false, },
          { value: "outer_peer", quoted: false, },
        ),
      ],
      [
        (
          { value: "rows", quoted: false, },
          { value: "inner_rows", quoted: false, },
        ),
      ],
    ],
  }
}

///|
test "Graph mapping resolves nearest producer without renaming definitions" {
  let parser = producer_scope_parser(
    "PROPERTY GRAPH (NODE TABLES (`ROWS` KEY (id) LABEL rows NO PROPERTIES) EDGE TABLES (catalog.edges AS E KEY (edge_id) SOURCE KEY (src) REFERENCES `ROWS` DESTINATION KEY (dst) REFERENCES `ROWS` LABEL R NO PROPERTIES))",
  )
  let mapping = parser.graph()
  parser.end()
  assert_eq(mapping.nodes[0].producer, [
    { value: "inner_rows", quoted: false, },
  ])
  assert_eq(mapping.nodes[0].name, { value: "ROWS", quoted: true, })
  assert_eq(mapping.nodes[0].labels[0].name, {
    value: "rows",
    quoted: false,
  })
  assert_eq(mapping.edges[0].producer, [
    { value: "catalog", quoted: false, },
    { value: "edges", quoted: false, },
  ])
  assert_eq(mapping.edges[0].source.definition, {
    value: "ROWS",
    quoted: true,
  })
  assert_eq(mapping.edges[0].destination.definition, {
    value: "ROWS",
    quoted: true,
  })
}

///|
test "SGA producer roles resolve scope while ID and field values remain data" {
  let parser = producer_scope_parser(
    "reach(start: {from: `ROWS`, id: 'rows'}, direction: 'out', max_depth: 2)",
  )
  let call = parser.sga_call()
  parser.end()
  assert_eq(call.arguments, [
    (
      "start",
      ObjectValue([
        ("from", Producer({ value: "inner_rows", quoted: false, })),
        ("id", TextValue("rows")),
      ]),
    ),
    ("direction", TextValue("out")),
    ("max_depth", NumberValue("2")),
  ])
  let list_parser = producer_scope_parser(
    "mean_graphs(with: [ROWS, peer], weights: [1, 2])",
  )
  let list = list_parser.sga_call()
  list_parser.end()
  assert_eq(list.arguments, [
    (
      "with",
      ListValue([
        Producer({ value: "inner_rows", quoted: false, }),
        Producer({ value: "outer_peer", quoted: false, }),
      ]),
    ),
    ("weights", ListValue([NumberValue("1"), NumberValue("2")])),
  ])
  let id_parser = producer_scope_parser("reach(start: 'rows')")
  assert_eq(id_parser.sga_call().arguments, [("start", TextValue("rows"))])
  id_parser.end()
}

///|
test "FROM GRAPH resolves the nearest binding before any Carrier check" {
  let parser = producer_scope_parser(
    "FROM GRAPH `ROWS` |> node_rows() |> SELECT id",
  )
  let query = parser.query()
  parser.end()
  assert_eq(relation(query), [{ value: "inner_rows", quoted: false, }])
  assert_eq(relation_alias(query), None)
  assert_true(graph_query(query) is Some(_))
  assert_eq(parser.cte_scopes.length(), 2)
  // Resolving does not search an outer Graph to repair a nearer type mismatch.
  // The common checker, not this parser, decides that Carrier validity.
  assert_eq(parser.resolve_cte([{ value: "rows", quoted: false, }]), [
    { value: "inner_rows", quoted: false, },
  ])
}
