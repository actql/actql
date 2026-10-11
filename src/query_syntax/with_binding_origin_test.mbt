///|
test "authored WITH names and original UTF-8 ranges survive scope binding" {
  let source = "WITH `é` AS (SELECT 1 AS id), second AS (FROM `é` |> SELECT id) SELECT id FROM second"
  let query = parse_query(source, query_limits(), source_path="bindings.sql").unwrap()
  assert_eq(query_binding_count(query), 2)
  let first = query_binding_at(query, 0).unwrap()
  let second = query_binding_at(query, 1).unwrap()
  // Independent counts of the authored UTF-8 source, not parser span output.
  assert_eq(first.origin, AuthoredWith({ value: "é", quoted: true, }, 5, 29))
  assert_eq(
    second.origin,
    AuthoredWith({ value: "second", quoted: false, }, 31, 65),
  )
  assert_false(first.carry_ranges)
  assert_false(second.carry_ranges)
  assert_eq(relation(second.query), [first.name])
  guard operation_at(first.query, 0) is Some(Select(projections)) else {
    fail("the authored producer retains its SELECT")
  }
  let expression = projections[0].expression.unwrap()
  let span = @origin.span(
    expression_origin(expression, expression_root(expression)).unwrap(),
  )
  assert_eq(span.source_path, "bindings.sql")
}

///|
test "internal Relation continuation is never an authored WITH declaration" {
  let query = parse_query(
    "SELECT id FROM (WITH selected AS (SELECT id FROM rows) SELECT id FROM selected)",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(query), 2)
  let selected = query_binding_at(query, 0).unwrap()
  let continuation = query_binding_at(query, 1).unwrap()
  match selected.origin {
    AuthoredWith(name, _, _) =>
      assert_eq(name, { value: "selected", quoted: false, })
    _ => fail("selected is authored")
  }
  assert_eq(continuation.origin, RelationalContinuation)
  assert_eq(relation(continuation.query), [selected.name])
  assert_eq(relation(query), [continuation.name])
  assert_eq(relation_alias(query), None)
}

///|
test "nested body resolves before its own authored WITH binding is introduced" {
  let query = parse_query(
    "WITH item AS (SELECT id FROM rows), chosen AS (WITH item AS (SELECT id FROM item) SELECT id FROM item) SELECT id FROM chosen",
    query_limits(),
  ).unwrap()
  assert_eq(query_binding_count(query), 3)
  let outer = query_binding_at(query, 0).unwrap()
  let inner = query_binding_at(query, 1).unwrap()
  let chosen = query_binding_at(query, 2).unwrap()
  match inner.origin {
    AuthoredWith(name, _, _) => assert_eq(name.value, "item")
    _ => fail("the inner binding is authored")
  }
  assert_true(inner.name != outer.name)
  assert_eq(relation(inner.query), [outer.name])
  assert_eq(relation(chosen.query), [inner.name])
  assert_eq(relation(query), [chosen.name])
}
