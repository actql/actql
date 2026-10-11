///|
test "P2 SGA selectors use operand column identifiers rather than String values" {
  let call = parse_sga_call(
    "reach(start: {from: seeds, id: `node.key`}, direction: 'out')",
    query_limits(),
  ).unwrap()
  assert_eq(call.arguments, [
    ("start", ObjectValue([
      ("from", Producer({ value: "seeds", quoted: false })),
      ("id", FieldReference([{ value: "node.key", quoted: true }])),
    ])),
    ("direction", TextValue("out")),
  ])
}

///|
test "P2 SGA Delta field and weight are references while definition labels are data" {
  let call = parse_sga_call("apply_graph_delta(with: changes, field: delta)", query_limits()).unwrap()
  assert_eq(call.arguments, [
    ("with", Producer({value: "changes", quoted: false})),
    ("field", FieldReference([{value: "delta", quoted: false}])),
  ])
  let weighted = parse_sga_call("shortest_path(source: 'A', target: 'B', weight: cost)", query_limits()).unwrap()
  assert_eq(weighted.arguments[2].1, FieldReference([{value: "cost", quoted: false}]))
}

///|
test "P2 SGA MATCH output bindings and selected fields accept identifiers" {
  let call = parse_sga_call(
    "match_edges(definition: 'E', label: 'R', bindings: {identity: edge_key, source: src, target: dst}, where: {literal: true}, fields: [edge_key, src, dst])",
    query_limits(),
  ).unwrap()
  assert_eq(call.arguments[0].1, TextValue("E"))
  assert_eq(call.arguments[1].1, TextValue("R"))
  assert_eq(call.arguments[2].1, ObjectValue([
    ("identity", OutputName({value: "edge_key", quoted: false})),
    ("source", OutputName({value: "src", quoted: false})),
    ("target", OutputName({value: "dst", quoted: false})),
  ]))
  assert_eq(call.arguments[4].1, ListValue([
    FieldReference([{value: "edge_key", quoted: false}]),
    FieldReference([{value: "src", quoted: false}]),
    FieldReference([{value: "dst", quoted: false}]),
  ]))
}

///|
test "P2 SGA predicate field paths stay references and literal field keys stay data" {
  let call = parse_sga_call(
    "match_nodes(where: {eq: [{field: payload.score}, {literal: {field: 'payload.score', id: 'A'}}]}, fields: [payload])",
    query_limits(),
  ).unwrap()
  assert_eq(call.arguments[0].1, ObjectValue([
    ("eq", ListValue([
      ObjectValue([("field", FieldReference([{value:"payload",quoted:false},{value:"score",quoted:false}]))]),
      ObjectValue([("literal", ObjectValue([("field",TextValue("payload.score")),("id",TextValue("A"))]))]),
    ])),
  ]))
}

///|
test "P2 SGA retired reference strings are rejected without changing literal IDs" {
  for text in [
    "reach(start: {from: seeds, id: 'id'})",
    "apply_graph_delta(with: changes, field: 'delta')",
    "shortest_path(source: 'A', target: 'B', weight: 'cost')",
    "match_nodes(where: {field: 'name'}, fields: [name])",
    "match_nodes(bindings: {identity: 'element'}, fields: [element])",
    "match_nodes(where: {literal: true}, fields: ['name'])",
  ] {
    assert_true(parse_sga_call(text,query_limits()) is Err(_), msg=text)
  }
  assert_eq(parse_sga_call("reach(start: 'id')",query_limits()).unwrap().arguments,
    [("start",TextValue("id"))])
}

///|
test "P2 SGA signed literal operands preserve spelling without evaluating expressions" {
  assert_eq(parse_sga_call("reach(start: 'A', max_depth: +2)",query_limits()).unwrap().arguments[1].1,
    NumberValue("+2"))
  for text in ["reach(start: 'A', max_depth: -@p)", "reach(start: 'A', max_depth: -(1))", "reach(start: 'A', max_depth: 1-2)"] {
    assert_true(parse_sga_call(text,query_limits()) is Err(_),msg=text)
  }
}
