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
