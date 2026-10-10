///|
test "traverse hop vocabulary folds while predicate data retains its spelling" {
  let actual = parse_sga_call(
    "TRAVERSE(START: {FROM: seeds, ID: 'element'}, HOPS: [{DIRECTION: 'out', EDGE_TYPES: [], NODE_WHERE: {eq: [{literal: {Direction: 'e\\u0301\\r', direction: 'x'}}, null]}}], EMIT: 'nodes')",
    query_limits(),
  ).unwrap()
  let expected = parse_sga_call(
    "traverse(start: {from: seeds, id: 'element'}, hops: [{direction: 'out', edge_types: [], node_where: {eq: [{literal: {Direction: 'e\\u0301\\r', direction: 'x'}}, null]}}], emit: 'nodes')",
    query_limits(),
  ).unwrap()
  assert_eq(actual.arguments, expected.arguments)
  guard actual.arguments[1].1 is ListValue([ObjectValue(fields)]) else {
    fail("expected a single typed hop")
  }
  assert_true(fields.contains(("direction", TextValue("out"))))
  guard fields[2].1
    is ObjectValue([(_, ListValue([ObjectValue([(_, ObjectValue(data))]), _]))]) else {
    fail("expected the unchanged literal object")
  }
  assert_eq(data, [
    ("Direction", TextValue("e\u0301\r")),
    ("direction", TextValue("x")),
  ])
}

///|
test "traverse duplicate hop vocabulary is rejected after name folding" {
  for
    text in [
      "traverse(hops: [{direction: 'out', DIRECTION: 'in'}])", "traverse(hops: [{edge_types: [], `EDGE_TYPES`: ['R']}])",
      "traverse(hops: [{node_where: true, NODE_WHERE: false}])",
    ] {
    assert_true(
      parse_sga_call(text, query_limits())
      is Err({ issue: Syntax("Duplicate SGA argument"), .. }),
      msg=text,
    )
  }
}
