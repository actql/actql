///|
test "Pipe aggregate scalar expressions retain private calls in copied syntax" {
  let query = parse_query(
    "FROM pair |> AGGREGATE COUNT(*) + 1 AS n GROUP BY x AS bucket",
    query_limits(),
  ).unwrap()
  guard operation_at(query, 0)
    is Some(Group(keys, projections, PipeAggregate(names, embedded))) else {
    fail("expected scalar aggregate metadata")
  }
  assert_eq(keys.length(), 1)
  assert_eq(projections.length(), 2)
  assert_eq(names, [Some({ value: "bucket", quoted: false, })])
  assert_eq(embedded, [{ value: "aql_select_aggregate_0", quoted: false, }])
  embedded.clear()
  names.clear()
  guard operation_at(query, 0)
    is Some(Group(_, _, PipeAggregate(retained, calls))) else {
    fail("expected independent metadata copies")
  }
  assert_eq(retained.length(), 1)
  assert_eq(calls.length(), 1)
}

///|
test "Pipe aggregate scalar expressions require an aggregate and output name" {
  for
    source in [
      "FROM pair |> AGGREGATE x + 1 AS n", "FROM pair |> AGGREGATE COUNT(*) + 1",
      "FROM pair |> AGGREGATE COUNT(*) + 1 AS n, x AS value", "FROM pair |> AGGREGATE COUNT(*) OVER () AS n",
      "FROM pair |> AGGREGATE *",
    ] {
    assert_true(parse_query(source, query_limits()) is Err(_), msg=source)
  }
}

///|
test "Pipe aggregate scalar expressions bind evaluated subtrees without losing source ownership" {
  let expression = parse_expression(
    "(x + 1) * 2",
    expression_limits(),
    source_path="aggregate.sql",
  ).unwrap()
  guard expression_node(expression, expression_root(expression))
    is Some({ kind: Binary(_, left, _), .. }) else {
    fail("expected binary expression")
  }
  let original = expression_node(expression, left).unwrap()
  let bound = expression_with_field_bindings(expression, [
    (left, { value: "private_key", quoted: false, }),
  ]).unwrap()
  guard expression_node(bound, expression_root(bound))
    is Some({ kind: Binary(_, receiver, _), .. }) else {
    fail("expected owned bound tree")
  }
  assert_eq(expression_node_count(bound), 3)
  let node = expression_node(bound, receiver).unwrap()
  assert_eq(node.kind, Reference([{ value: "private_key", quoted: false, }]))
  assert_eq(node.start, original.start)
  assert_eq(node.end, original.end)
  assert_eq(expression_work(bound), expression_work(expression))
  assert_eq(
    @origin.span(expression_origin(bound, receiver).unwrap()).source_path,
    "aggregate.sql",
  )
  assert_true(
    expression_node(expression, left).unwrap().kind is Parenthesized(_),
  )
  assert_true(
    expression_with_field_bindings(expression, [
      (-1, { value: "invalid", quoted: false, }),
    ])
    is None,
  )
  assert_true(
    expression_with_field_bindings(expression, [
      (left, { value: "one", quoted: false, }),
      (left, { value: "two", quoted: false, }),
    ])
    is None,
  )
}
