///|
test "Parameter Type phase funds original views work two paths and normalization without default bodies" {
  let root = cursor("{\"type\":\"number\"}")
  let g = @value_contract.observe_parameter_read_construction_geometry(root)
  let inventory = @value_contract.parameter_read_phase_construction_inventory(
    g,
    1L,
    { max_nodes: 100, max_depth: 2, max_text_bytes: 1000, },
  ).unwrap()
  // Existing type6H10R12W plus actual syntax/default/meta carrier5H9R5W.
  assert_eq(
    (
      inventory.returned.record_headers,
      inventory.returned.reference_slots,
      inventory.returned.scalar_words,
    ),
    (11L, 19L, 17L),
  )
  assert_eq(
    (
      inventory.temporary.record_headers,
      inventory.temporary.reference_slots,
      inventory.temporary.scalar_words,
    ),
    (123L, 347L, 263L),
  )
  let n = inventory.normalization.unwrap()
  assert_eq(
    (n.record_headers, n.reference_slots, n.scalar_words, n.owned_utf16_units),
    (100L, 123L, 690L, 122L),
  )
  assert_eq(inventory.sort_fields, 0)
  assert_true(@value_contract.read_parameter_syntax(root, limits()) is Ok(_))
}

///|
test "wide Parameter fields retain actual builtin key-check branch and field multiplicity" {
  let fields = Array::makei(32, i => {
    "\"p" + i.to_string() + "\":{\"type\":\"number\"}"
  })
  let root = cursor(
    "{\"type\":\"object\",\"fields\":{" + fields.join(",") + "}}",
  )
  let g = @value_contract.observe_parameter_read_construction_geometry(root)
  assert_eq((g.types, g.objects, g.fields, g.max_view_fields), (33, 1, 32, 32))
  let inventory = @value_contract.parameter_read_phase_construction_inventory(
    g,
    1L,
    { max_nodes: 100, max_depth: 5, max_text_bytes: 10000, },
  ).unwrap()
  assert_eq(
    (
      inventory.returned.record_headers,
      inventory.returned.reference_slots,
      inventory.returned.scalar_words,
    ),
    (273L, 685L, 405L),
  )
  assert_eq(inventory.sort_fields, 32)
  let keys = @shape.object_key_construction_counts(32, 0, 32).unwrap()
  assert_eq(
    (keys.maps, keys.map_entries, keys.pair_arrays, keys.pairs),
    (3, 96L, 2, 64L),
  )
  assert_eq(
    (
      inventory.temporary.record_headers,
      inventory.temporary.reference_slots,
      inventory.temporary.scalar_words,
    ),
    (1089L, 3617L, 3053L),
  )
  let actual = @value_contract.read_parameter_syntax(root, {
    max_nodes: 100,
    max_depth: 5,
    max_text_bytes: 10000,
  }).unwrap()
  guard actual.parameter_type.rule is @value_contract.Properties(fields) else {
    fail("actual original object type")
  }
  assert_eq(@value_contract.parameter_fields(fields).length(), 32)
  assert_true(
    @value_contract.parameter_read_phase_construction_inventory(
      { ..g, fields: -1, },
      1L,
      limits(),
    )
    is None,
  )
  assert_true(
    @value_contract.parameter_read_phase_construction_inventory(
      g,
      -1L,
      limits(),
    )
    is None,
  )
}
