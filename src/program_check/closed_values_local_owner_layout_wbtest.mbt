///|
test "closed Values carrier upper retains exact Timestamp comparison syntax" {
  assert_true(closed_values_local_owner_layout(-1) is None)
  let shallow = closed_values_local_owner_layout(0).unwrap()
  // Independent inventory: 6986 sites / 11473 slots. Against the previous
  // comparison this reserves two headers, three references and four words,
  // or 88 bytes in either representation; all other owner terms are unchanged.
  assert_eq(
    (shallow.record_headers, shallow.reference_slots, shallow.scalar_words),
    (14137L, 18847L, 25738L),
  )
  assert_eq((shallow.owned_utf16_units, shallow.owned_wire_bytes), (142L, 0L))
  let deeper = closed_values_local_owner_layout(1).unwrap()
  assert_eq(
    (deeper.record_headers, deeper.reference_slots, deeper.scalar_words),
    (14140L, 18859L, 25753L),
  )
}
