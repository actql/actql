///|
test "unnamed projected table closes ranges while a Pipe table preserves its actual scope" {
  let projected = parse_query("SELECT id FROM (SELECT 1 AS id)", query_limits()).unwrap()
  assert_eq(relation_alias(projected), None)
  assert_false(query_binding_at(projected, 0).unwrap().carry_ranges)
  let ranged = parse_query(
    "SELECT r.x FROM (FROM rows |> AS r)",
    query_limits(),
  ).unwrap()
  assert_eq(relation_alias(ranged), None)
  assert_true(query_binding_at(ranged, 0).unwrap().carry_ranges)
  let named = parse_query(
    "SELECT current.x FROM (FROM rows |> AS r) current",
    query_limits(),
  ).unwrap()
  assert_eq(relation_alias(named), None)
  let named_body = query_binding_at(named, 0).unwrap()
  assert_true(named_body.carry_ranges)
  assert_true(
    operation_at(named_body.query, operation_count(named_body.query) - 1)
    is Some(Alias({ value: "current", quoted: false, })),
  )
  let projected_named = parse_query(
    "SELECT current.x FROM (SELECT x FROM rows) current",
    query_limits(),
  ).unwrap()
  assert_eq(
    relation_alias(projected_named),
    Some({ value: "current", quoted: false, }),
  )
  assert_false(query_binding_at(projected_named, 0).unwrap().carry_ranges)
}

///|
test "parenthesized set operands close their input aliases" {
  let query = parse_query(
    "(FROM rows |> AS old) UNION ALL BY NAME (FROM rows |> AS other)",
    query_limits(),
  ).unwrap()
  assert_false(query_binding_at(query, 0).unwrap().carry_ranges)
  assert_eq(query_binding_count(query), 2)
  assert_false(query_binding_at(query, 1).unwrap().carry_ranges)
}
