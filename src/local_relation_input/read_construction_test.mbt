///|
fn declaration_quantity_cursor(text : String) -> @decode.Cursor {
  let node = @source.parse_json(text, {
    max_input_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  @decode.admit(node, {
    max_nodes: 10000,
    max_depth: 100,
    max_string_bytes: 100000,
    max_total_string_bytes: 100000,
  }).unwrap()
}

///|
test "local declaration quantity preserves key order and raw enum DATA on the same original source" {
  let enumerant = Array::make(400, "é").join("")
  let wire = "{\"carrier\":\"relation\",\"expected_columns\":[\"x\"],\"schema\":{\"x\":{\"type\":\"string\",\"nullable\":false,\"enum\":[\"" +
    enumerant +
    "\"]}},\"primary_key\":[\"x\"],\"duplicates\":{\"first_by_order\":{\"order_by\":[{\"x\":\"asc\"}]}}}"
  let original = declaration_quantity_cursor(wire)
  let g = observe_read_construction_geometry(original)
  assert_eq(g.expected_names, 1)
  assert_eq(g.key_fields, 1)
  assert_eq(g.order_keys, 1)
  // Raw enum DATA is not an identifier-normalization workspace.
  assert_true(g.max_name_utf16_units < 64)
  assert_true(g.inspection_work > 0L)
  let inventory = read_construction_inventory(g).unwrap()
  assert_true(inventory.retained.record_headers > 0L)
  assert_true(inventory.scratch.reference_slots > 0L)
  let checked = read(original, {
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  assert_true(physical_equal(source(checked), original))
  assert_true(primary_key(checked) is Some(_))
  assert_true(has_first_by_order(checked))
}

///|
test "local declaration geometry does not repair invalid carrier key or missing schema field" {
  let limits : Limits = {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }
  for
    wire in [
      "{\"carrier\":\"wrong\"}", "{\"carrier\":\"relation\",\"primary_key\":[]}",
      "{\"carrier\":\"relation\",\"expected_columns\":[\"y\"],\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
    ] {
    let original = declaration_quantity_cursor(wire)
    assert_true(
      read_construction_inventory(observe_read_construction_geometry(original))
      is Some(_),
    )
    assert_true(read(original, limits) is Err(_))
  }
}
