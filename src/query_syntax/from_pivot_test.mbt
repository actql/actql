///|
test "FROM PIVOT isolates input and output aliases in a projected producer" {
  let query = parse_query(
    "SELECT result.opened FROM orders input PIVOT(COUNT(input.amount) FOR input.status IN ('open' AS opened)) result WHERE result.opened > 0",
    query_limits(),
  ).unwrap()
  assert_eq(cte_count(query), 1)
  let child = cte_at(query, 0).unwrap().query
  assert_eq(relation(child).map(name => name.value), ["orders"])
  assert_eq(relation_alias(child), Some({ value: "input", quoted: false, }))
  assert_true(operation_at(child, 0) is Some(Pivot(_)))
  assert_eq(relation_alias(query), Some({ value: "result", quoted: false, }))
  assert_true(operation_at(query, 0) is Some(Where(_)))
}

///|
test "FROM PIVOT quoted aliases stay names rather than clause starters" {
  let query = parse_query(
    "SELECT `ORDER`.opened FROM orders `PIVOT` PIVOT(COUNT(`PIVOT`.amount) FOR `PIVOT`.status IN ('open' AS opened)) `ORDER`",
    query_limits(),
  ).unwrap()
  assert_eq(
    relation_alias(cte_at(query, 0).unwrap().query),
    Some({ value: "PIVOT", quoted: true, }),
  )
  assert_eq(relation_alias(query), Some({ value: "ORDER", quoted: true, }))
}
