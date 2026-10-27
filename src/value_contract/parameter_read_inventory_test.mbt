///|
test "Parameter returned type inventory uses actual typed positions and the original collection owner" {
  let original = cursor(
    "{\"type\":\"array\",\"items\":{\"type\":\"object\",\"fields\":{\"v\":{\"type\":\"string\",\"enum\":[\"a\",\"b\"]}}},\"default\":[{\"v\":\"a\"}],\"meta\":{\"note\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}}}",
  )
  let g = @value_contract.observe_parameter_read_construction_geometry(original)
  assert_eq(
    (g.types, g.arrays, g.objects, g.fields, g.enumerants, g.enumeration_arrays),
    (3, 1, 1, 1, 2, 1),
  )
  let inventory = @value_contract.parameter_read_construction_inventory(g).unwrap()
  // Original three types18H30R36W; one field pair2H4R; enum2H2R1W.
  // Three actual vectors (two object projections and enum) hold four items.
  assert_eq(
    (inventory.records, inventory.record_references, inventory.record_words),
    (22L, 36L, 37L),
  )
  assert_eq((inventory.reference_arrays, inventory.reference_items), (3L, 4L))
  let extent = @shape.collection_construction_extent(inventory).unwrap()
  assert_eq(
    (extent.record_headers, extent.reference_slots, extent.scalar_words),
    (31L, 87L, 43L),
  )
  // The semantic owner still validates the same exact declaration once here.
  let actual = @value_contract.read_parameter_syntax(original, limits()).unwrap()
  guard actual.parameter_type.rule is @value_contract.Items(item, ..) else {
    fail("array type")
  }
  guard item.rule is @value_contract.Properties(fields) else {
    fail("object type")
  }
  assert_eq(@value_contract.parameter_fields(fields).length(), 1)
}

///|
test "Parameter constructor inventory keeps empty enum vector and refuses forged negative quantities" {
  let g = @value_contract.observe_parameter_read_construction_geometry(
    cursor("{\"type\":\"string\",\"enum\":[]}"),
  )
  assert_eq((g.types, g.enumeration_arrays, g.enumerants), (1, 1, 0))
  let i = @value_contract.parameter_read_construction_inventory(g).unwrap()
  assert_eq((i.reference_arrays, i.reference_items), (1L, 0L))
  assert_true(
    @value_contract.parameter_read_construction_inventory({ ..g, fields: -1, })
    is None,
  )
  assert_true(
    @value_contract.parameter_read_construction_inventory({
      ..g,
      enumeration_arrays: 2,
    })
    is None,
  )
  assert_true(
    @value_contract.parameter_read_construction_inventory({
      ..g,
      arrays: 1,
      objects: 1,
    })
    is None,
  )
}
