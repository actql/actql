///|
fn graph_call(query : @syntax.Query) -> @syntax.SgaCall {
  guard @syntax.operation_at(query, 0) is Some(GraphCall(call)) else {
    abort("fixture Graph call missing")
  }
  call
}

///|
test "argument origins use the original document and immutable occurrence copies" {
  let query = @syntax.parse_query(
    "FROM g |> components(kind: 'weak')",
    syntax_limits(),
  ).unwrap()
  let document = @syntax.query_document(query)
  let call = graph_call(query)
  let original = @syntax.sga_argument_origin(call, 0, document).unwrap()
  assert_eq(@origin.kind(original), Authored)
  let span = @origin.span(original)
  assert_eq((span.start_byte, span.end_byte), (27, 33))
  assert_true(@origin.belongs_to(document, original))
  let copy = graph_call(query)
  assert_eq(call, copy)
  call.arguments[0] = ("kind", TextValue("invented"))
  assert_true(@syntax.sga_argument_origin(call, 0, document) is None)
  assert_true(@syntax.sga_argument_origin(copy, 0, document) is Some(_))
  assert_true(
    @syntax.sga_argument_origin(graph_call(query), 0, document) is Some(_),
  )
}

///|
test "equal text from a foreign parsed document cannot reuse argument origins" {
  let text = "FROM g |> components(kind: 'weak')"
  let first = @syntax.parse_query(text, syntax_limits()).unwrap()
  let second = @syntax.parse_query(text, syntax_limits()).unwrap()
  let call = graph_call(first)
  assert_eq(call, graph_call(second))
  assert_true(
    @syntax.sga_argument_origin(call, 0, @syntax.query_document(second)) is None,
  )
  assert_true(
    @syntax.sga_argument_origin(call, -1, @syntax.query_document(first)) is None,
  )
  assert_true(
    @syntax.sga_argument_origin(call, 1, @syntax.query_document(first)) is None,
  )
}

///|
test "deep object and list mutation cannot retarget parser argument provenance" {
  let query = @syntax.parse_query(
    "FROM g |> components(kind: {nested: [1]})",
    syntax_limits(),
  ).unwrap()
  let document = @syntax.query_document(query)
  let call = graph_call(query)
  let copy = graph_call(query)
  guard call.arguments[0].1 is ObjectValue(fields) else {
    fail("expected object")
  }
  guard fields[0].1 is ListValue(items) else { fail("expected list") }
  items[0] = NumberValue("2")
  assert_true(@syntax.sga_argument_origin(call, 0, document) is None)
  assert_true(@syntax.sga_argument_origin(copy, 0, document) is Some(_))
  assert_true(
    @syntax.sga_argument_origin(graph_call(query), 0, document) is Some(_),
  )
  copy.arguments[0] = ("other", copy.arguments[0].1)
  assert_true(@syntax.sga_argument_origin(copy, 0, document) is None)
}

///|
test "argument snapshot work remains charged to the query parser budget" {
  let limits = syntax_limits()
  assert_true(
    @syntax.parse_query("FROM g |> components(kind: {nested: [1, 2, 3]})", {
      ..limits,
      max_work: 1,
    })
    is Err(_),
  )
}

///|
test "Sequence predicate owners survive argument snapshots without a second parse" {
  let query = @syntax.parse_query_script(
      "FROM records |> sequence(by: [], id: id, time: occurred_ms, pattern: [{as: first, where: kind = 1}, {as: second, where: kind = 2}], within: 20, overlap: 'allow', contiguity: 'adjacent')",
      syntax_limits(),
    ).unwrap()
    |> @syntax.script_query
  let call = graph_call(query)
  let copy = graph_call(query)
  let document = @syntax.query_document(query)
  assert_eq(call, copy)
  guard call.arguments[3].1 is ListValue(parts) &&
    parts[0] is ObjectValue(fields) &&
    fields[1].1 is ExpressionValue(predicate) else {
    fail("original predicate expected")
  }
  let expression = @syntax.sga_predicate_expression(predicate)
  for i in 0..<@syntax.expression_node_count(expression) {
    let node = @syntax.expression_node(expression, i).unwrap()
    if node.kind is Reference(path) {
      path.clear()
    }
  }
  assert_true(@syntax.sga_argument_origin(call, 3, document) is Some(_))
  assert_true(
    @origin.belongs_to(
      document,
      @syntax.expression_origin(expression, @syntax.expression_root(expression)).unwrap(),
    ),
  )
  parts.clear()
  assert_true(@syntax.sga_argument_origin(call, 3, document) is None)
  assert_true(@syntax.sga_argument_origin(copy, 3, document) is Some(_))
}

///|
test "argument snapshot has an independently fixed exact work boundary" {
  // Six consumed tokens plus the three-token named-argument snapshot charge.
  let source = "components(kind: 'weak')"
  let limits = syntax_limits()
  assert_true(
    @syntax.parse_sga_call(source, { ..limits, max_work: 9, }) is Ok(_),
  )
  assert_true(
    @syntax.parse_sga_call(source, { ..limits, max_work: 8, }) is Err(_),
  )
}
