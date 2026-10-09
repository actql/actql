///|
test "Graph merge container vocabulary has typed case-insensitive names" {
  for operation in ["union_graphs", "subtract_graphs"] {
    let call = parse_sga_call(
      operation + "(WITH: peer, MERGE: {NODE_PROPERTIES: {p: 'number_sum'}, `Edge_Properties`: {w: 'number_mean'}})",
      query_limits(),
    ).unwrap()
    assert_eq(call.arguments, [
      ("with", Producer({ value: "peer", quoted: false, })),
      ("merge", ObjectValue([
        ("node_properties", ObjectValue([("p", TextValue("number_sum"))])),
        ("edge_properties", ObjectValue([("w", TextValue("number_mean"))])),
      ])),
    ])
  }
}

///|
test "Graph merge rejects duplicate typed vocabulary before lowering" {
  for operation in ["union_graphs", "subtract_graphs"] {
    for fields in [
      "node_properties: {}, NODE_PROPERTIES: {}",
      "edge_properties: {}, `Edge_Properties`: {}",
    ] {
      let text = operation + "(with: peer, merge: {" + fields + "})"
      assert_true(
        parse_sga_call(text, query_limits()) is Err({ issue: Syntax("Duplicate SGA argument"), .. }),
        msg=text,
      )
    }
  }
}

///|
test "Graph merge preserves authored property names and strategy values" {
  for operation in ["union_graphs", "subtract_graphs"] {
    let call = parse_sga_call(
      operation + "(merge: {node_properties: {Score: 'NUMBER_SUM', score: 'number_sum'}, edge_properties: {Node_Properties: 'e\\u0301\\r'}})",
      query_limits(),
    ).unwrap()
    assert_eq(call.arguments, [
      ("merge", ObjectValue([
        ("node_properties", ObjectValue([
          ("Score", TextValue("NUMBER_SUM")), ("score", TextValue("number_sum")),
        ])),
        ("edge_properties", ObjectValue([("Node_Properties", TextValue("e\u0301\r"))])),
      ])),
    ])
  }
}
