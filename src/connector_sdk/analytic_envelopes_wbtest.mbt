///|
test "analytic envelopes retain exact occurrence ceilings" {
  let value = analytic_envelope(1, 2L, 3L, 4L, 5L, 6L).unwrap()
  assert_eq(analytic_envelope_step(value), 1)
  assert_eq(analytic_envelope_input_wire_bytes(value), 2L)
  assert_eq(analytic_envelope_output_wire_bytes(value), 3L)
  assert_eq(analytic_envelope_partition_wire_bytes(value), 4L)
  assert_eq(analytic_envelope_frame_memberships(value), 5L)
  assert_eq(analytic_envelope_output_rows(value), 6L)
  let snapshot = snapshot_analytic_envelopes([value], 2).unwrap()
  assert_true(
    physical_equal(find_analytic_envelope(snapshot, 1).unwrap(), value),
  )
  assert_true(find_analytic_envelope(snapshot, 0) is None)
}

///|
test "analytic envelopes reject invalid and duplicate occurrences" {
  assert_true(analytic_envelope(-1, 0L, 0L, 0L, 0L, 0L) is Err(InvalidLimits))
  assert_true(analytic_envelope(0, -1L, 0L, 0L, 0L, 0L) is Err(InvalidLimits))
  let value = analytic_envelope(0, 1L, 1L, 1L, 1L, 1L).unwrap()
  assert_true(snapshot_analytic_envelopes([value], 0) is None)
  assert_true(snapshot_analytic_envelopes([value, value], 1) is None)
  assert_true(snapshot_analytic_envelopes([], -1) is None)
}
