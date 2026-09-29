///|
test "captured Effect context requires explicit dependency inventory without repair" {
  assert_true(
    admit_captured_effect_source_dependencies([], "[]", 10000, 1000, 32)
    is Ok(_),
  )
  for wire in ["null", "{}", " []", "[{\"kind\":\"caller_root\"}]"] {
    assert_true(
      admit_captured_effect_source_dependencies([], wire, 10000, 1000, 32)
      is Err(_),
    )
  }
  let explicit = parse_contract_wire(
    "{\"effect_source_local_inventory\":{},\"effect_dependency_inventory\":[]}",
    10000, 1000, 32,
  ).unwrap()
  assert_true(
    captured_effect_context_dependencies_valid(explicit, 10000, 1000, 32),
  )
  for
    wire in [
      "{\"effect_source_local_inventory\":{}}", "{\"effect_source_local_inventory\":{},\"effect_dependency_inventory\":null}",
      "{\"effect_source_local_inventory\":{},\"effect_dependency_inventory\":{}}",
      "{\"effect_dependency_inventory\":[]}", "{\"effect_source_local_inventory\":{\"write\":{}},\"effect_dependency_inventory\":[]}",
    ] {
    assert_false(
      captured_effect_context_dependencies_valid(
        parse_contract_wire(wire, 10000, 1000, 32).unwrap(),
        10000,
        1000,
        32,
      ),
    )
  }
}
