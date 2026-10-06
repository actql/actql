///|
test "partition expressions retain precedence and actual source origins" {
  let text = "SELECT ROW_NUMBER() OVER (PARTITION BY amount > 1, CASE WHEN id = 1 THEN 'a' ELSE 'b' END ORDER BY id) AS pos FROM orders"
  let query = parse_query(text, query_limits(), source_path="partition.sql").unwrap()
  match operation_at(query, 0) {
    Some(Analytic(projections)) => {
      let keys = projections[0].analytic.unwrap().window.partition_by
      assert_eq(keys.length(), 2)
      let root = expression_node(keys[0], expression_root(keys[0])).unwrap()
      assert_true(root.kind is Binary(">", _, _))
      assert_eq(root.start, 39)
      assert_eq(root.end, 49)
      let span = @origin.span(
        expression_origin(keys[0], expression_root(keys[0])).unwrap(),
      )
      assert_eq(span.source_path, "partition.sql")
      assert_eq(span.start_column, 40)
      assert_eq(span.end_column, 50)
      assert_true(
        expression_node(keys[1], expression_root(keys[1])).unwrap().kind
        is SearchedCase(_, _),
      )
    }
    _ => fail("partition keys must keep their ordinary expression owner")
  }
}

///|
test "partition expression syntax retains ordinary parser limits and clause boundaries" {
  for
    text in [
      "SELECT ROW_NUMBER() OVER (PARTITION BY amount + ORDER BY id) AS pos FROM orders",
      "SELECT ROW_NUMBER() OVER (PARTITION BY id, ORDER BY id) AS pos FROM orders",
      "SELECT ROW_NUMBER() OVER (PARTITION BY (id > 1 ORDER BY id) AS pos FROM orders",
    ] {
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=text,
    )
  }
  let text = "SELECT ROW_NUMBER() OVER (PARTITION BY id + 1 ORDER BY id) AS pos FROM orders"
  let baseline = query_limits()
  assert_true(
    parse_query(text, {
      ..baseline,
      expression: { ..baseline.expression, max_nodes: 1, },
    })
    is Err(_),
  )
}
