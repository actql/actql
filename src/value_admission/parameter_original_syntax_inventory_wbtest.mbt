///|
test "original syntax Value inventory borrows String and retains actual mixed Decimal precision" {
  let original = @contract.read_parameter_syntax(
    json_steps_cursor(
      "{\"type\":\"object\",\"fields\":{\"text\":{\"type\":\"string\"},\"amount\":{\"type\":\"decimal\",\"precision\":4,\"scale\":2}}}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let root = json_steps_cursor(
    "{\"text\":\"" + "x".repeat(4096) + "\",\"amount\":\"12.34\"}",
  )
  let geometry = @decode.observe_subtree_construction_geometry(root)
  let inventory = parameter_syntax_value_body_construction_inventory(
    original, geometry,
  ).unwrap()
  assert_eq(@contract.parameter_syntax_maximum_decimal_precision(original), 4)
  assert_eq(inventory.owned_value_utf16_units, 10L)
  assert_eq(inventory.owned_decimal_scratch_utf16_units, 14L)
  assert_eq(
    Some(inventory),
    parameter_value_body_construction_inventory(
      original.parameter_type,
      geometry,
    ),
  )
  let actual = admit(original.parameter_type.contract, root, {
    max_nodes: 3,
    max_depth: 1,
    max_text_bytes: 4111,
  }).unwrap()
  assert_true(physical_equal(actual.contract, original.parameter_type.contract))
  guard actual.value is Object(fields) else { abort("original default") }
  guard element_at(fields, 0) is Some(("amount", Decimal(amount))) else {
    abort("actual Decimal")
  }
  assert_eq(amount.coefficient, "1234")
  guard element_at(fields, 1) is Some(("text", Text(text))) else {
    abort("borrowed String")
  }
  assert_eq(text.length(), 4096)
}

///|
test "retained original syntax path covers nested fields and arrays without another type walk" {
  let original = @contract.read_parameter_syntax(
    json_steps_cursor(
      "{\"type\":\"array\",\"items\":{\"type\":\"object\",\"fields\":{\"amount\":{\"type\":\"decimal\",\"precision\":8,\"scale\":2}}}}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let root = json_steps_cursor(
    "[{\"amount\":\"-12.30\"},{\"amount\":\"0.00\"}]",
  )
  let geometry = @decode.observe_subtree_construction_geometry(root)
  let inventory = parameter_syntax_value_body_construction_inventory(
    original, geometry,
  ).unwrap()
  assert_eq(@contract.parameter_syntax_maximum_decimal_precision(original), 8)
  assert_eq(inventory.owned_value_utf16_units, 18L)
  assert_eq(inventory.owned_decimal_scratch_utf16_units, 20L)
  assert_eq(
    Some(inventory),
    parameter_value_body_construction_inventory(
      original.parameter_type,
      geometry,
    ),
  )
  let actual = admit(original.parameter_type.contract, root, {
    max_nodes: 5,
    max_depth: 2,
    max_text_bytes: 23,
  }).unwrap()
  assert_eq(
    typed_steps_wire(actual),
    "[{\"amount\":\"-12.30\"},{\"amount\":\"0.00\"}]",
  )
}

///|
test "retained syntax inventory preserves original geometry rejection and nondecimal zero" {
  let original = @contract.read_parameter_syntax(
    json_steps_cursor("{\"type\":\"string\"}"),
    { max_nodes: 10, max_depth: 2, max_text_bytes: 100, },
  ).unwrap()
  let geometry = @decode.observe_subtree_construction_geometry(
    json_steps_cursor("\"" + "x".repeat(4096) + "\""),
  )
  let inventory = parameter_syntax_value_body_construction_inventory(
    original, geometry,
  ).unwrap()
  assert_eq(
    (
      inventory.owned_value_utf16_units,
      inventory.owned_decimal_scratch_utf16_units,
    ),
    (0L, 0L),
  )
  assert_true(
    parameter_syntax_value_body_construction_inventory(original, {
      ..geometry,
      nodes: 0,
    })
    is None,
  )
  assert_true(
    parameter_syntax_value_body_construction_inventory(original, {
      ..geometry,
      total_utf16: -1L,
    })
    is None,
  )
  assert_eq(
    parameter_syntax_value_body_construction_inventory(original, {
      ..geometry,
      fields: 1,
    }),
    parameter_value_body_construction_inventory(original.parameter_type, {
      ..geometry,
      fields: 1,
    }),
  )
}
