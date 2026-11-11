///|
test "single Relation constructor quote follows original geometry not output ceilings" {
  let view = saved_relation_view()
  let quote = fn(limits) {
    single_relation_declaration_construction_inventory(
      view.schema_wire.length(),
      12,
      2,
      2,
      1,
      4,
      15,
      11,
      limits,
    ).unwrap()
  }
  let first = quote(declaration_limits)
  let larger = quote({
    ..declaration_limits,
    max_bytes: declaration_limits.max_bytes + 1,
  })
  assert_true(first == larger)
  assert_true(first.record_headers > 0L)
  let original = generate_relation_row_declaration(
    "content-fixture",
    "fixture",
    "fixture/0.1",
    [{ ..view, resource_kind: "relation", }],
    declaration_limits,
  ).unwrap()
  assert_eq(original.views.length(), 1)
}

///|
test "single Relation construction refuses invalid and overflowing geometry" {
  assert_true(
    single_relation_declaration_construction_inventory(
      -1, 1, 1, 2, 1, 4, 7, 11, declaration_limits,
    )
    is None,
  )
  assert_true(
    single_relation_declaration_construction_inventory(
      100, 10, 1, 2, 1, 2147483647, 2147483647, 2147483647, declaration_limits,
    )
    is None,
  )
  assert_true(
    single_relation_declaration_construction_inventory(
      100,
      10,
      1,
      2,
      1,
      4,
      7,
      11,
      { ..declaration_limits, max_nodes: 0, },
    )
    is None,
  )
}

///|
test "single Relation quote funds fixed nonempty facts and writer refusal prefix" {
  let absent = single_relation_declaration_construction_inventory(
    100, 10, 1, 2, 1, 4, 7, 11, declaration_limits,
  ).unwrap()
  let facts = single_relation_declaration_construction_inventory(
    100, 10, 1, 47, 5, 4, 7, 11, declaration_limits,
  ).unwrap()
  assert_true(facts.owned_utf16_units > absent.owned_utf16_units)
  let refused = single_relation_declaration_construction_inventory(
    100,
    10,
    1,
    47,
    5,
    4,
    7,
    11,
    { ..declaration_limits, max_bytes: 1, max_nodes: 1, },
  ).unwrap()
  assert_true(refused.record_headers > 0L)
}
