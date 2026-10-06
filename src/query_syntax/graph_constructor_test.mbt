///|
test "Graph distinguishes producers definitions labels and columns" {
  let parsed = parse_graph(
    "PROPERTY GRAPH (NODE TABLES (`node input` AS N KEY (tenant, id) LABEL Person PROPERTIES (name AS display)) EDGE TABLES (edges AS E KEY (edge_id) SOURCE KEY (src_tenant, src) REFERENCES N (tenant, id) DESTINATION KEY (dst_tenant, dst) REFERENCES N LABEL R NO PROPERTIES))",
    query_limits(),
  ).unwrap()
  assert_eq(parsed.nodes, [
    {
      producer: [{ value: "node input", quoted: true, }],
      name: { value: "N", quoted: false, },
      key: [
        { value: "tenant", quoted: false, },
        { value: "id", quoted: false, },
      ],
      labels: [
        {
          name: { value: "Person", quoted: false, },
          properties: Columns([
            (
              { value: "name", quoted: false, },
              { value: "display", quoted: false, },
            ),
          ]),
        },
      ],
    },
  ])
  assert_eq(parsed.edges[0].source.referenced_key, Some(parsed.nodes[0].key))
  assert_eq(parsed.edges[0].destination.referenced_key, None)
  assert_eq(parsed.edges[0].labels, [
    { name: { value: "R", quoted: false, }, properties: NoProperties, },
  ])
}

///|
test "Graph preserves omitted properties versus explicit no properties" {
  let parsed = parse_graph(
    "PROPERTY GRAPH (NODE TABLES (rows AS N KEY (id), rows AS M KEY (id) NO PROPERTIES))",
    query_limits(),
  ).unwrap()
  assert_eq(parsed.nodes[0].labels, [
    { name: { value: "N", quoted: false, }, properties: AllColumns, },
  ])
  assert_eq(parsed.nodes[1].labels, [
    { name: { value: "M", quoted: false, }, properties: NoProperties, },
  ])
  assert_true(parsed.edges.is_empty())
}

///|
test "Graph retains multiple static labels and quoted spelling" {
  let parsed = parse_graph(
    "PROPERTY GRAPH (NODE TABLES (rows AS `Node definition` KEY (`Key`) DEFAULT LABEL PROPERTIES ARE ALL COLUMNS EXCEPT (`Private`) LABEL Person PROPERTIES (`Key` AS `Visible key`)))",
    query_limits(),
  ).unwrap()
  assert_eq(parsed.nodes[0].labels, [
    {
      name: { value: "Node definition", quoted: true, },
      properties: AllColumnsExcept([{ value: "Private", quoted: true, }]),
    },
    {
      name: { value: "Person", quoted: false, },
      properties: Columns([
        (
          { value: "Key", quoted: true, },
          { value: "Visible key", quoted: true, },
        ),
      ]),
    },
  ])
}

///|
test "Graph refuses unsupported mapping syntax without reinterpretation" {
  for
    text in [
      "PROPERTY GRAPH (NODE TABLES (rows))", "PROPERTY GRAPH (NODE TABLES (rows KEY ()))",
      "PROPERTY GRAPH (NODE TABLES (rows KEY (id) LABEL Person PROPERTIES (id + 1 AS next)))",
      "PROPERTY GRAPH (NODE TABLES (rows KEY (id) DYNAMIC LABEL (kind)))", "PROPERTY GRAPH (NODE TABLES (rows KEY (id)) EDGE TABLES (edges KEY (id) SOURCE KEY (src) REFERENCES missing.part DESTINATION KEY (dst) REFERENCES rows))",
      "CREATE GRAPH g NODE TABLES (rows KEY (id))", "graph(nodes: {from: rows, id: \"id\"})",
    ] {
    assert_true(parse_graph(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "Graph uses existing source and syntax work bounds" {
  let text = "PROPERTY GRAPH (NODE TABLES (rows KEY (id)))"
  for
    limits in [
      { ..query_limits(), max_syntax_nodes: 0, },
      { ..query_limits(), max_work: 0, },
      { ..query_limits(), max_work: -1, },
      {
        ..query_limits(),
        lexical: { ..query_limits().lexical, max_source_bytes: 1, },
      },
    ] {
    assert_true(parse_graph(text, limits) is Err(_))
  }
  let error = parse_graph(
    "PROPERTY GRAPH (NODE TABLES (rows KEY ()))",
    query_limits(),
    source_path="constructor.aql",
  ).unwrap_err()
  assert_true(error.span is Some(_))
}
