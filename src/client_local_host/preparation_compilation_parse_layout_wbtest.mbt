///|
test "compilation parse layout owns canonical strings once and excludes indexed cursor" {
  let facts : ClosedValuesLexicalFacts = {
    input_bytes: 7,
    node_upper: 2,
    objects: 1,
    arrays: 0,
    fields_upper: 1,
    quoted_tokens: 1,
    quoted_utf16_units: 1,
    longest_quoted_utf16: 1,
    longest_atom_utf16: 1,
    depth_upper: 1,
  }
  let q = compilation_parse_layout(facts, 1).unwrap()
  let c = compilation_canonical_layout({
    nodes: 2,
    objects: 1,
    arrays: 0,
    fields: 1,
    depth: 1,
    largest_object: 1,
  }).unwrap()
  assert_eq(q.value.record_headers, c.tree.record_headers + 1L)
  assert_eq(q.value.owned_utf16_units, 1L)
  assert_eq(q.value.owned_wire_bytes, 0L)
  assert_eq(q.temporary.owned_wire_bytes, 7L)
  assert_true(q.temporary.owned_utf16_units >= 7L)
  assert_true(compilation_parse_layout({ ..facts, node_upper: 0, }, 1) is None)
}
