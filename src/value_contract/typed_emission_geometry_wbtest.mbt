///|
test "typed scalar geometry agrees with actual checked emission" {
  let number = primitive(NumberType, nullable=false)
  let array = array_contract(number, nullable=true, max_items=Some(12L)).unwrap()
  let wide = object_contract(
    Array::makei(129, i => ("k" + i.to_string(), array)),
    nullable=false,
    max_fields=129,
    max_name_bytes=10000,
  ).unwrap()
  let text = string_enum_contract(
    ["a", "é", "😀"],
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
    nullable=false,
  ).unwrap()
  for contract in [number, array, wide, text] {
    let geometry = checked_emission_geometry(contract).unwrap()
    let out = @encode.measuring_writer(
      1000000,
      geometry.value_nodes,
      geometry.depth,
    )
    emit_checked(contract, out)
    let (_, nodes, depth) = @encode.finish_measurement_usage(out)
    assert_eq(nodes, geometry.value_nodes)
    assert_eq(depth, geometry.depth)
  }
  assert_eq(checked_emission_geometry(wide).unwrap().contract_nodes, 259)
  assert_eq(checked_emission_geometry(wide).unwrap().max_fields, 129)
  assert_eq(checked_emission_geometry(text).unwrap().enum_items, 3)
}

///|
test "typed geometry rejects depth before descending below the selected bound" {
  let number = primitive(NumberType, nullable=false)
  let array = array_contract(number, nullable=false, max_items=None).unwrap()
  let object = object_contract(
    [("value", array)],
    nullable=false,
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let full = checked_emission_geometry(object).unwrap()
  assert_eq(checked_emission_geometry(object, max_depth=full.depth), Some(full))
  assert_eq(checked_emission_geometry(object, max_depth=full.depth - 1), None)
  assert_eq(checked_emission_geometry(number, max_depth=0), None)
  assert_eq(checked_emission_geometry(array, max_depth=1), None)
}
