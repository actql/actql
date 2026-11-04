///|
test "Preview construction includes original retained row and ordered vectors" {
  let run = preview_identity_test_cid("b")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let a = preview_identity_test_cid("a")
  let template = preview_identity_test_wire(
    run,
    authoring,
    preview_identity_test_cid("4"),
    "001000000000001",
    a,
    a,
  )
  let (wire, _) = author_effect_preview_semantic_wire(
    template, run, authoring, 8192, 256, 12,
  ).unwrap()
  let original = admit_effect_preview_identity(
    wire, run, authoring, 8192, 256, 12,
  ).unwrap()
  // Inspect actual original backing, including spare capacity. Ordered
  // vectors retain the same row Strings, not fresh B-byte payloads per row.
  let mut slots = 0L
  let mut units = 0L
  for
    groups in [
      original.row_keys,
      original.row_cids,
      original.row_correlation_wires,
      original.row_intended_change_states,
      original.row_intended_value_wires,
      original.row_guard_version_cids,
      original.ordered_row_correlation_wires,
      original.ordered_row_intended_change_states,
      original.ordered_row_intended_value_wires,
      original.row_order,
    ] {
    slots += groups.capacity().to_int64()
    for row in groups {
      slots += row.capacity().to_int64()
      for value in row {
        units += value.length().to_int64()
      }
    }
  }
  let quote = effect_preview_identity_construction_inventory(8192, 256, 12).unwrap()
  assert_true(quote.reference_slots >= slots)
  assert_true(quote.owned_utf16_units >= units)
  assert_eq(original.row_correlation_wires[0][0], "\"001000000000001\"")
  assert_eq(
    original.ordered_row_intended_value_wires[0][0],
    original.row_intended_value_wires[0][0],
  )
  // The quotation itself admits no semantic identity: a mismatching original
  // Run still fails at the existing checker with the original typed issue.
  assert_true(
    admit_effect_preview_identity(wire, a, authoring, 8192, 256, 12)
    is Err(RunBindingMismatch),
  )
}

///|
test "Preview construction refuses invalid limits and keeps refused prefixes" {
  assert_true(effect_preview_identity_construction_inventory(0, 1, 1) is None)
  assert_true(effect_preview_identity_construction_inventory(1, 0, 1) is None)
  assert_true(effect_preview_identity_construction_inventory(1, 1, 0) is None)
  let prefix = effect_preview_identity_construction_inventory(1, 1, 1).unwrap()
  // A one-byte document cannot be a valid Preview, but parser/identity
  // refusal constructors still need funding before that verdict exists.
  assert_true(prefix.record_headers > 0L)
  assert_true(prefix.owned_wire_bytes >= 1L)
  assert_true(admit_effect_preview_identity("{", "", "", 1, 1, 1) is Err(_))
}
