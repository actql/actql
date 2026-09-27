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
