///|
test "binding Header quantity uses original declarations and actual supplied width not its admitted ceiling" {
  let definitions = declarations("{\"x\":{\"type\":\"number\"}}")
  let original = @parameter_binding.prepare_binding_read(
    definitions,
    Some(cursor("{\"x\":7}")),
    values_limit(),
  ).unwrap()
  let n = @parameter_binding.binding_header_construction_extent(original, 0).unwrap()
  assert_eq(
    (n.record_headers, n.reference_slots, n.scalar_words),
    (57L, 158L, 78L),
  )
  let wide = "{" +
    Array::makei(9, i => "\"k" + i.to_string() + "\":null").join(",") +
    "}"
  let original = @parameter_binding.prepare_binding_read(
    definitions,
    Some(cursor(wide)),
    values_limit(),
  ).unwrap()
  let n = @parameter_binding.binding_header_construction_extent(original, 0).unwrap()
  assert_eq(
    (n.record_headers, n.reference_slots, n.scalar_words),
    (202L, 599L, 506L),
  )
  @parameter_binding.advance_binding_read(original)
  assert_true(
    @parameter_binding.binding_read_phase(original) ==
    @parameter_binding.BindingComplete,
  )
  assert_true(
    @parameter_binding.binding_header_construction_extent(original, 0) is None,
  )
}

///|
test "absent binding Header retains original empty arrays and complete outcome without supplied Map" {
  let definitions = declarations("{\"x\":{\"type\":\"number\"}}")
  let original = @parameter_binding.prepare_binding_read(
    definitions,
    None,
    values_limit(),
  ).unwrap()
  let n = @parameter_binding.binding_header_construction_extent(original, 0).unwrap()
  assert_eq(
    (n.record_headers, n.reference_slots, n.scalar_words),
    (26L, 70L, 29L),
  )
  assert_true(
    @parameter_binding.binding_header_construction_extent(original, -1) is None,
  )
  @parameter_binding.advance_binding_read(original)
  assert_true(
    @parameter_binding.binding_read_phase(original) ==
    @parameter_binding.BindingSelection,
  )
  assert_true(@parameter_binding.binding_read_pending_source(original) is None)
}
