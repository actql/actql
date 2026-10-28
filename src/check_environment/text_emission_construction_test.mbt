///|
test "original Member text inventory uses saved emission geometry and exact serializer" {
  let body = "{\"x\":[\"é😀\",null]}"
  let environment = member_geometry_environment(body)
  let original = member_at(environment, MappingContracts, 0).unwrap()
  assert_eq(member_emission_geometry(original), (21, 4, 2))
  let quantity = member_text_emission_construction_extent(original)
  // Four nodes, two open containers; pending Object/Array/Visit peak is3.
  // Shared traversal25H50R24W plus text writer56H114R122W; no CID or wire.
  assert_eq(quantity, {
    record_headers: 81L,
    reference_slots: 164L,
    scalar_words: 146L,
    owned_utf16_units: 114L,
    owned_wire_bytes: 0L,
  })
  for cap in [20, 21] {
    let output = @encode.writer(cap, 4, 2)
    let result = try {
      emit_member(original, output)
      Some(@encode.finish_text_usage(output))
    } catch {
      @encode.OutputLimit => None
      _ => abort("original member emission failure changed")
    }
    if cap == 21 {
      assert_eq(result, Some((body, 21, 4, 2)))
    } else {
      assert_true(result is None)
    }
  }
  assert_eq(member_text_emission_construction_extent(original), quantity)
  assert_true(physical_equal(member_environment(original), environment))
  assert_true(wire_text_construction_extent(-1, 1, 0) is None)
  assert_true(wire_text_construction_extent(1, 0, 0) is None)
  assert_true(wire_text_construction_extent(1, 1, -1) is None)
}
