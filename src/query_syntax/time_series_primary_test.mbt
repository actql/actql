///|
test "time-series primary is Relation syntax and its accessor cannot mutate the source" {
  let query = parse_query(
    "WITH grid AS (time_series(start: '2026-10-12T00:00:00.000Z', end: '2026-10-12T00:03:00.000Z', step: '1m')) SELECT time FROM grid",
    query_limits(),
  ).unwrap()
  let body = query_binding_at(query, 0).unwrap().query
  assert_true(graph_query(body) is None)
  guard producer_primary(body) is Some(RelationGenerator(call)) else {
    fail("the generator is not a Graph primary")
  }
  assert_eq(call.arguments.length(), 3)
  call.arguments.clear()
  guard producer_primary(body) is Some(RelationGenerator(original)) else {
    fail("accessor changed the Query")
  }
  assert_eq(original.arguments.length(), 3)
  let projected = after_relation_generator(body, {
    value: "private",
    quoted: true,
  }).unwrap()
  assert_true(producer_primary(projected) is None)
  assert_true(relation(projected).is_empty())
  assert_eq(bound_source(projected), Some({ value: "private", quoted: true, }))
}
