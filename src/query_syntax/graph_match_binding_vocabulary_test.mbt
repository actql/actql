///|
test "Graph match binding vocabulary folds without rewriting output names" {
  let call = parse_sga_call(
    "MATCH_EDGES(BINDINGS: {IDENTITY: 'Edge', `Source`: 'Source', TARGET: 'Target'})",
    query_limits(),
  ).unwrap()
  assert_eq(call.arguments, [
    (
      "bindings",
      ObjectValue([
        ("identity", TextValue("Edge")),
        ("source", TextValue("Source")),
        ("target", TextValue("Target")),
      ]),
    ),
  ])
}

///|
test "Graph match duplicate binding roles reject after folding" {
  for
    text in [
      "match_nodes(bindings: {identity: 'first', IDENTITY: 'second'})", "match_edges(bindings: {source: 'first', `Source`: 'second'})",
    ] {
    assert_true(
      parse_sga_call(text, query_limits())
      is Err({ issue: Syntax("Duplicate SGA argument"), .. }),
      msg=text,
    )
  }
}

///|
test "Graph match bindings do not fold unrelated literal property data" {
  let call = parse_sga_call(
    "match_nodes(bindings: {identity: 'Element'}, where: {eq: [{literal: {Identity: 'e\\u0301\\r', identity: 'x'}}, null]})",
    query_limits(),
  ).unwrap()
  guard call.arguments[1].1
    is ObjectValue(
      [(_, ListValue([ObjectValue([(_, ObjectValue(fields))]), _]))]
    ) else {
    fail("expected an unchanged literal object")
  }
  assert_eq(fields, [
    ("Identity", TextValue("e\u0301\r")),
    ("identity", TextValue("x")),
  ])
}
