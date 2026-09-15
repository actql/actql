///|
test "join estimates retain both occurrences and distinguish input work from pair work" {
  let rows = sum_dispatch_quantities([Some(2L), Some(3L)]).unwrap()
  let bytes = sum_dispatch_quantities([Some(7L), Some(11L)]).unwrap()
  let pairs = dispatch_pair_quantity(Some(2L), Some(3L)).unwrap()
  let rate : @cost.WorkRate = {
    work_slots: [0],
    fixed_ms: Some(1L),
    per_row_ms: Some(2L),
    per_wire_byte_ms: Some(3L),
    per_pair_ms: Some(4L),
  }
  let schedule = @cost.prepare_rate_schedule(1, [rate], 10).unwrap()
  assert_eq(
    @cost.evaluate_rate_schedule(schedule, rows, bytes, pairs).unwrap()[0].milliseconds,
    Some(89L),
  )
  assert_eq(sum_dispatch_quantities([Some(7L), Some(7L)]).unwrap(), Some(14L))
  assert_eq(sum_dispatch_quantities([Some(7L), None]).unwrap(), None)
  assert_eq(dispatch_pair_quantity(Some(0L), None).unwrap(), Some(0L))
  assert_eq(dispatch_pair_quantity(Some(2L), None).unwrap(), None)
  assert_eq(
    @cost.evaluate_rate_schedule(schedule, rows, bytes, None).unwrap()[0].milliseconds,
    None,
  )
  assert_eq(
    @cost.evaluate_rate_schedule(
      @cost.prepare_rate_schedule(1, [{ ..rate, per_pair_ms: Some(0L), }], 10).unwrap(),
      rows,
      bytes,
      None,
    ).unwrap()[0].milliseconds,
    Some(65L),
  )
  assert_true(
    dispatch_pair_quantity(Some(9223372036854775807L), Some(2L))
    is Err(EstimateOverflow),
  )
  assert_true(
    sum_dispatch_quantities([Some(9223372036854775807L), Some(1L)])
    is Err(EstimateOverflow),
  )
}
