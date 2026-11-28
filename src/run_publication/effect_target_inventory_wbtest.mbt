///|
/// Canonical target identity order is shared Effect meaning. Return only
/// original source indexes so callers retain each request and observation
/// owner together; this inventory is neither a read nor write permission.
fn derive_effect_target_row_inventory(
  target_wires : Array[String],
  max_rows : Int,
  max_total_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[Int], EffectPreviewIdentityIssue] {
  if max_rows < 0 ||
    max_total_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    target_wires.length() > max_rows {
    return Err(Encoding)
  }
  let mut remaining_bytes = max_total_bytes
  let targets : Array[(String, Int)] = []
  for index, wire in target_wires {
    if wire.length() > remaining_bytes {
      return Err(Encoding)
    }
    let bytes = @utf8.encode(wire)
    if bytes.length() > remaining_bytes {
      return Err(Encoding)
    }
    remaining_bytes -= bytes.length()
    let value = match
      parse_contract_wire(
        wire,
        bytes.length(),
        max_nodes,
        max_depth,
        data_keys=true,
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidMember)
    }
    let canonical = @json.stringify_value(
      value, max_total_bytes, max_nodes, max_depth,
    ) catch {
      _ => return Err(Encoding)
    }
    targets.push((canonical, index))
  }
  order_effect_target_inventory(targets)
}

///|
test "target order retains original indexes and exact canonical data keys" {
  assert_eq(
    derive_effect_target_row_inventory(
      ["\"c-key\"", "\"b-key\"", "\"a-key\""],
      3,
      128,
      16,
      4,
    ).unwrap(),
    [2, 1, 0],
  )
  assert_eq(
    derive_effect_target_row_inventory(
      ["{\"b\":1,\"a\":2}", "{\"a\":1}"],
      2,
      128,
      16,
      4,
    ).unwrap(),
    [1, 0],
  )
  // NFC and NFD are different data, not a duplicate operational identity.
  assert_eq(
    derive_effect_target_row_inventory(["\"é\"", "\"é\""], 2, 128, 16, 4).unwrap(),
    [1, 0],
  )
}

///|
test "duplicate canonical target identity is refused rather than collapsed" {
  assert_true(
    derive_effect_target_row_inventory(
      ["{\"b\":1,\"a\":2}", "{\"a\":2,\"b\":1}"],
      2,
      128,
      16,
      4,
    )
    is Err(InvalidMember),
  )
  assert_true(
    derive_effect_target_row_inventory(["\"a\"", "\"a\""], 2, 128, 16, 4)
    is Err(InvalidMember),
  )
}

///|
test "target inventory preserves byte node depth and row bounds" {
  assert_true(
    derive_effect_target_row_inventory(["\"a\""], 0, 128, 16, 4)
    is Err(Encoding),
  )
  assert_true(
    derive_effect_target_row_inventory(["\"é\""], 1, 3, 16, 4) is Err(Encoding),
  )
  assert_true(
    derive_effect_target_row_inventory(["{\"a\":{\"b\":1}}"], 1, 128, 16, 1)
    is Err(_),
  )
  assert_true(
    derive_effect_target_row_inventory(["{\"a\":1}"], 1, 128, 1, 4) is Err(_),
  )
  assert_true(
    derive_effect_target_row_inventory(["{\"a\":1,\"a\":2}"], 1, 128, 16, 4)
    is Err(InvalidMember),
  )
}
