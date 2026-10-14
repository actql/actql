///|
test "listing installation declaration preserves exact amounts without resource admission" {
  let declared = client_program_row_source_listing_report_capacity(7L, 9L).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(declared), 7L)
  assert_eq(@execution.execution_capacity_execution_bytes(declared), 9L)
  // This DATA constructor has neither a Ledger nor an acquisition. Only the
  // existing Source start can reserve/own the declaration's complete envelope.
}

///|
test "listing installation rejects absent positive retention or short execution" {
  for (retained, executing) in [
    (0L, 0L),
    (0L, 9L),
    (-1L, 9L),
    (7L, 6L),
    (7L, -1L),
  ] {
    assert_true(
      client_program_row_source_listing_report_capacity(retained, executing)
      is None,
    )
  }
}
