///|
fn query_limits() -> QueryLimits {
  {
    lexical: limits(),
    expression: expression_limits(),
    max_syntax_nodes: 100,
    max_cte_count: 20,
    max_work: 10000,
  }
}

///|
test "SQL and Pipe query pair preserves ordered operations" {
  let sql = parse_query(
    "SELECT id, customer_id, amount FROM orders WHERE status = 'open' ORDER BY amount DESC, id ASC;",
    query_limits(),
  ).unwrap()
  let pipe = parse_query(
    "FROM orders |> WHERE status = 'open' |> SELECT id, customer_id, amount |> ORDER BY amount DESC, id ASC;",
    query_limits(),
  ).unwrap()
  for query in [sql, pipe] {
    assert_eq(relation(query), [{ value: "orders", quoted: false, }])
    assert_eq(operation_count(query), 3)
    match operation_at(query, 0) {
      Some(Where(predicate)) =>
        assert_true(
          expression_node(predicate, expression_root(predicate)).unwrap().kind
          is Binary("=", _, _),
        )
      _ => fail("expected source filter")
    }
    match operation_at(query, 1) {
      Some(Select(columns, false)) => {
        assert_eq(columns.length(), 3)
        let names = ["id", "customer_id", "amount"]
        for index in 0..<names.length() {
          match columns[index].expression {
            Some(expression) =>
              assert_eq(
                expression_node(expression, expression_root(expression)).unwrap().kind,
                Reference([{ value: names[index], quoted: false, }]),
              )
            None => fail("expected explicit projected column")
          }
        }
      }
      _ => fail("expected projection")
    }
    match operation_at(query, 2) {
      Some(Order(terms)) => {
        assert_eq(terms.length(), 2)
        assert_eq(terms[0].direction, "desc")
        assert_eq(terms[0].nulls, "last")
        assert_eq(terms[1].direction, "asc")
        assert_eq(terms[1].nulls, "first")
      }
      _ => fail("expected total sort")
    }
  }
}

///|
test "query source clauses reject partial and unsupported input" {
  for
    text in [
      "SELECT a FROM", "SELECT a FROM t WHERE", "SELECT a FROM t ORDER BY", "SELECT a FROM t LIMIT -1",
      "SELECT a FROM t LIMIT 1.5", "SELECT a FROM t ORDER BY a; SELECT b FROM t",
      "FROM t |> DELETE a",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "noncorrelated FROM subqueries keep bounded dataflow and source alias" {
  let sql = parse_query(
    "SELECT s.id FROM (SELECT id FROM orders WHERE id > 1) AS s",
    query_limits(),
  ).unwrap()
  assert_eq(cte_count(sql), 1)
  assert_eq(relation(sql), [cte_at(sql, 0).unwrap().name])
  assert_eq(relation_alias(sql), Some({ value: "s", quoted: false, }))
  assert_eq(relation(cte_at(sql, 0).unwrap().query), [
    { value: "orders", quoted: false, },
  ])
  let ordered = parse_query(
    "SELECT s.id FROM (SELECT id FROM orders ORDER BY id LIMIT 2) AS s",
    query_limits(),
  ).unwrap()
  assert_eq(operation_count(cte_at(ordered, 0).unwrap().query), 3)
  let pipe = parse_query(
    "FROM (SELECT id FROM orders WHERE id > 1) AS s |> SELECT s.id",
    query_limits(),
  ).unwrap()
  assert_eq(cte_count(pipe), 1)
  assert_eq(relation_alias(pipe), relation_alias(sql))
  let nested = parse_query(
    "SELECT outer_rows.id FROM (SELECT inner_rows.id FROM (SELECT id FROM orders) AS inner_rows) AS outer_rows",
    query_limits(),
  ).unwrap()
  assert_eq(cte_count(nested), 2)
  assert_eq(relation(cte_at(nested, 1).unwrap().query), [
    cte_at(nested, 0).unwrap().name,
  ])
  assert_true(
    parse_query(
      "SELECT outer_rows.id FROM (SELECT inner_rows.id FROM (SELECT id FROM orders) AS inner_rows) AS outer_rows",
      { ..query_limits(), max_cte_count: 1, },
    )
    is Err(_),
  )
  assert_true(
    parse_query("SELECT id FROM (SELECT id FROM orders)", query_limits())
    is Err(_),
  )
}

///|
test "LIMIT and OFFSET admit only exact safe integers" {
  let query = parse_query(
    "SELECT id FROM orders LIMIT 9007199254740991 OFFSET 9007199254740991",
    query_limits(),
  ).unwrap()
  match operation_at(query, operation_count(query) - 1) {
    Some(Limit(count, offset)) => {
      assert_eq(count, 9007199254740991L)
      assert_eq(offset, 9007199254740991L)
    }
    _ => fail("expected admitted LIMIT")
  }
  for
    text in [
      "SELECT id FROM orders LIMIT 0", "SELECT id FROM orders LIMIT 9007199254740992",
      "SELECT id FROM orders LIMIT 1 OFFSET 9007199254740992", "SELECT id FROM orders LIMIT 1.5",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "SQL set operators keep explicit multiplicity and final ordering" {
  let parsed = parse_query(
    "SELECT a, b FROM left_rows UNION ALL SELECT c, d FROM right_rows ORDER BY a LIMIT 4",
    query_limits(),
  ).unwrap()
  assert_eq(set_part_count(parsed), 1)
  let part = set_part_at(parsed, 0).unwrap()
  assert_eq((part.kind, part.duplicates, part.by_name), ("union", "all", false))
  assert_eq(relation(part.right), [{ value: "right_rows", quoted: false, }])
  assert_eq(final_operation_count(parsed), 2)
  assert_true(final_operation_at(parsed, 0) is Some(Order(_)))
  assert_true(final_operation_at(parsed, 1) is Some(Limit(4L, 0L)))
  let named = parse_query(
    "SELECT a, b FROM left_rows INTERSECT DISTINCT BY NAME SELECT b, a FROM left_rows",
    query_limits(),
  ).unwrap()
  assert_true(set_part_at(named, 0).unwrap().by_name)
  for
    text in [
      "SELECT a FROM left_rows INTERSECT ALL SELECT a FROM left_rows", "SELECT a FROM left_rows UNION SELECT a FROM left_rows",
      "SELECT a FROM left_rows UNION ALL SELECT a FROM left_rows EXCEPT DISTINCT SELECT a FROM left_rows",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "Pipe set inputs are parenthesized and retain final ordering" {
  let parsed = parse_query(
    "FROM left_rows |> SELECT a, b |> UNION ALL (SELECT c, d FROM right_rows) |> ORDER BY a |> LIMIT 4",
    query_limits(),
  ).unwrap()
  assert_eq(set_part_count(parsed), 1)
  let part = set_part_at(parsed, 0).unwrap()
  assert_eq((part.kind, part.duplicates, part.by_name), ("union", "all", false))
  assert_eq(final_operation_count(parsed), 2)
  for
    text in [
      "FROM left_rows |> UNION ALL SELECT c, d FROM right_rows", "FROM left_rows |> UNION ALL (SELECT c, d FROM right_rows) |> WHERE a > 1",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "SQL JOIN retains qualifier and equality condition" {
  let query = parse_query(
    "SELECT l.a AS a, r.d AS d FROM left_rows AS l LEFT JOIN right_rows AS r ON l.a = r.c",
    query_limits(),
  ).unwrap()
  assert_eq(join_part_count(query), 1)
  let part = join_part_at(query, 0).unwrap()
  assert_eq(part.kind, "left")
  assert_eq(part.relation, [{ value: "right_rows", quoted: false, }])
  assert_eq(part.source_alias, Some({ value: "r", quoted: false, }))
  assert_true(part.on is Some(_))
  let implicit_alias = parse_query(
    "SELECT l.a AS a, r.d AS d FROM left_rows l JOIN right_rows r ON l.a = r.c",
    query_limits(),
  ).unwrap()
  assert_eq(
    relation_alias(implicit_alias),
    Some({ value: "l", quoted: false, }),
  )
  assert_eq(
    join_part_at(implicit_alias, 0).unwrap().source_alias,
    Some({ value: "r", quoted: false, }),
  )
  let piped = parse_query(
    "FROM left_rows AS l |> LEFT JOIN right_rows AS r ON l.a = r.c |> SELECT l.a AS a, r.d AS d",
    query_limits(),
  ).unwrap()
  assert_eq(join_part_count(piped), 1)
  assert_eq(join_part_at(piped, 0).unwrap().kind, "left")
  for
    text in [
      "SELECT l.a FROM left_rows AS l JOIN right_rows AS r ON l.a > r.c", "SELECT l.a FROM left_rows AS l RIGHT JOIN right_rows AS r ON l.a = r.c",
    ] {
    let parsed = parse_query(text, query_limits())
    if text.contains("RIGHT JOIN") {
      assert_true(parsed is Err(_))
    } else {
      assert_true(parsed is Ok(_))
    }
  }
}

///|
test "nonrecursive CTE names retain declaration order and bounds" {
  let query = parse_query(
    "WITH first AS (SELECT a FROM left_rows), second AS (SELECT a FROM first) SELECT a FROM second",
    query_limits(),
  ).unwrap()
  assert_eq(cte_count(query), 2)
  assert_eq(cte_at(query, 0).unwrap().name.value, "first")
  assert_eq(relation(cte_at(query, 1).unwrap().query)[0].value, "first")
  assert_eq(relation(query)[0].value, "second")
  assert_true(
    parse_query("WITH first AS (SELECT a FROM left_rows) SELECT a FROM first", {
      ..query_limits(),
      max_cte_count: 0,
    })
    is Err(_),
  )
  for
    text in [
      "WITH RECURSIVE c AS (SELECT a FROM c) SELECT a FROM c", "WITH c AS (SELECT a FROM left_rows), c AS (SELECT a FROM left_rows) SELECT a FROM c",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}
