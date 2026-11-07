///|
test "captured native JSON composes the original Source key peak once with native frame and scalar controls" {
  let number = json_construction_extent(25, 1, 1, normalize_keys=false).unwrap()
  for (nodes, depth) in [(54, 3), (1000, 2), (1, 1), (2147483647, 2147483647)] {
    let tree = json_construction_extent(1, nodes, depth, normalize_keys=false).unwrap()
    let captured = captured_json_construction_extent(nodes, depth).unwrap()
    // The Source recipe already owns active key maps. Native admission adds
    // one borrowed-key FixedArray per open frame and one serial Number parser.
    assert_eq(
      captured.record_headers,
      tree.record_headers +
      Int::min(nodes, depth).to_int64() +
      number.record_headers,
    )
    assert_eq(
      captured.reference_slots,
      tree.reference_slots + nodes.to_int64() + number.reference_slots,
    )
    assert_eq(captured.scalar_words, tree.scalar_words + number.scalar_words)
    assert_eq(captured.owned_utf16_units, 25L + number.owned_utf16_units)
  }
  assert_true(captured_json_construction_extent(0, 1) is None)
  assert_true(captured_json_construction_extent(1, 0) is None)
  assert_true(captured_json_construction_extent(-1, 1) is None)
  assert_true(
    captured_json_construction_extent(54, 3, normalize_keys=true, key_units=-1L)
    is None,
  )
  assert_true(
    captured_json_construction_extent(
      54,
      3,
      normalize_keys=true,
      key_units=1L,
      max_key_units=2,
    )
    is None,
  )
}
