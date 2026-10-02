///|
test "SGA calls distinguish producer references ID values and column designations" {
  let reach = parse_sga_call(
    "reach(start: {from: `seed rows`, id: \"node key\"}, direction: 'out', max_depth: 2)",
    query_limits(),
  ).unwrap()
  assert_eq(reach.operation, "reach")
  assert_eq(reach.arguments, [
    (
      "start",
      ObjectValue([
        ("from", Producer({ value: "seed rows", quoted: true, })),
        ("id", TextValue("node key")),
      ]),
    ),
    ("direction", TextValue("out")),
    ("max_depth", NumberValue("2")),
  ])
  let single = parse_sga_call("reach(start: 'A')", query_limits()).unwrap()
  assert_eq(single.arguments, [("start", TextValue("A"))])
  let apply = parse_sga_call(
    "apply_graph_delta(with: changes, field: 'delta')",
    query_limits(),
  ).unwrap()
  assert_eq(apply.arguments, [
    ("with", Producer({ value: "changes", quoted: false, })),
    ("field", TextValue("delta")),
  ])
}

///|
test "SGA explicit Graph lists never add an implicit current producer" {
  let call = parse_sga_call(
    "mean_graphs(with: [first, `second graph`], weights: [1, 2])",
    query_limits(),
  ).unwrap()
  assert_eq(call.arguments, [
    (
      "with",
      ListValue([
        Producer({ value: "first", quoted: false, }),
        Producer({ value: "second graph", quoted: true, }),
      ]),
    ),
    ("weights", ListValue([NumberValue("1"), NumberValue("2")])),
  ])
}

///|
test "SGA uses the complete adopted closed operation vocabulary" {
  for
    operation in [
      "reach", "traverse", "shortest_path", "components", "degree", "graph_bounds",
      "match_nodes", "match_edges", "normalize_graph", "subgraph", "graft_graph",
      "union_graphs", "subtract_graphs", "graphs_equal", "graph_diff", "apply_graph_delta",
      "mean_graphs", "node_rows", "edge_rows",
    ] {
    assert_eq(
      parse_sga_call(operation + "()", query_limits()).unwrap().operation,
      operation,
    )
  }
  assert_eq(
    parse_sga_call("COMPONENTS(KIND: 'weak')", query_limits()).unwrap().arguments,
    [("kind", TextValue("weak"))],
  )
}

///|
test "SGA rejects string producer references duplicate arguments and malformed calls" {
  for
    text in [
      "reach(start: {from: 'seeds', id: 'id'})", "traverse(start: {from: \"seeds\", id: 'id'})",
      "shortest_path(source: {from: 'seeds'})", "shortest_path(target: {from: 'seeds'})",
      "subgraph(nodes: {from: 'selected'})", "graphs_equal(with: 'peer')", "mean_graphs(with: [first, 'second'])",
      "reach(start: {from: seeds, FROM: other})", "components(kind: 'weak', KIND: 'strong')",
      "components(kind: weak)", "`components`(kind: 'weak')", "another_graph_algorithm()",
      "OP reach {}", "normalize_graph() trailing", "mean_graphs(with: [first,])",
      "components(kind: 'weak',)", "reach(start: {from: seeds,})",
    ] {
    assert_true(parse_sga_call(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "SGA preserves decoded strings and exact numeric spelling" {
  let call = parse_sga_call(
    "reach(start: \"e\\u0301\\r\", max_depth: 9007199254740993, max_output_rows: @bound)",
    query_limits(),
  ).unwrap()
  assert_eq(call.arguments, [
    ("start", TextValue("e\u0301\r")),
    ("max_depth", NumberValue("9007199254740993")),
    ("max_output_rows", ParameterValue("bound")),
  ])
  // Syntax does not round a numeric token or validate its operation-specific
  // range. Ordinary lowering/admission/checking still owns those obligations.
  assert_eq(
    parse_sga_call("reach(start: r'A\\n' 'B')", query_limits()).unwrap().arguments,
    [("start", TextValue("A\\nB"))],
  )
  let literal = parse_sga_call(
    "match_nodes(where: {eq: [{literal: {Name: 'x', name: 'y'}}, null]})",
    query_limits(),
  ).unwrap()
  assert_eq(literal.arguments, [
    (
      "where",
      ObjectValue([
        (
          "eq",
          ListValue([
            ObjectValue([
              (
                "literal",
                ObjectValue([("Name", TextValue("x")), ("name", TextValue("y"))]),
              ),
            ]),
            NullValue,
          ]),
        ),
      ]),
    ),
  ])
}

///|
test "SGA parser shares work node depth and original source position limits" {
  let text = "--😀\r\nreach(start: {from: seeds, id: 'id'})"
  let call = parse_sga_call(text, query_limits()).unwrap()
  assert_eq(call.start, 8)
  assert_eq(call.end, text.length() + 2)
  assert_true(
    parse_sga_call(text, { ..query_limits(), max_syntax_nodes: 1, }) is Err(_),
  )
  assert_true(
    parse_sga_call(text, { ..query_limits(), max_work: 1, }) is Err(_),
  )
  assert_true(
    parse_sga_call(text, {
      ..query_limits(),
      expression: { ..query_limits().expression, max_depth: 0, },
    })
    is Err(_),
  )
  let bad = parse_sga_call(
    "--😀\r\nreach(start: {from: 'seeds'})",
    query_limits(),
    source_path="bad-sga.aql",
  ).unwrap_err().span.unwrap()
  assert_eq(bad.source_path, "bad-sga.aql")
  assert_eq(bad.start_line, 2)
  assert_eq(bad.start_column, 21)
  let nested = StringBuilder()
  nested.write_string("match_nodes(where: ")
  for _ in 0..<33 {
    nested.write_string("[")
  }
  nested.write_string("true")
  for _ in 0..<33 {
    nested.write_string("]")
  }
  nested.write_string(")")
  assert_true(
    parse_sga_call(nested.to_string(), {
      ..query_limits(),
      expression: { ..query_limits().expression, max_depth: 128, },
    })
    is Err(_),
  )
  for invalid in [-1, 2147483647] {
    assert_true(
      parse_sga_call("normalize_graph()", {
        ..query_limits(),
        max_syntax_nodes: invalid,
      })
      is Err({ issue: InvalidLimits, .. }),
    )
  }
}
