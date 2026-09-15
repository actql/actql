///|
fn fixed_rate(slots : Array[Int], fixed : Int64) -> WorkRate {
  {
    work_slots: slots,
    fixed_ms: Some(fixed),
    per_row_ms: Some(0L),
    per_wire_byte_ms: Some(0L),
    per_pair_ms: Some(0L),
  }
}

///|
test "rate schedules snapshot arbitrary implementation inventories and returned coverage" {
  let slots = [0, 2]
  let rates = [fixed_rate(slots, 7L), fixed_rate([1], 11L)]
  let schedule = prepare_rate_schedule(3, rates, 8).unwrap()
  assert_eq(rate_schedule_work(schedule), 8)
  slots[0] = 99
  rates.clear()
  let first = evaluate_rate_schedule(schedule, None, None, None).unwrap()
  assert_eq(assess_serial(3, first, 8).unwrap(), Complete(18L))
  first[0].work_slots.clear()
  let second = evaluate_rate_schedule(schedule, None, None, None).unwrap()
  assert_eq(assess_serial(3, second, 8).unwrap(), Complete(18L))
  assert_eq(second[0].work_slots, [0, 2])
}

///|
test "rate schedules preserve unknown quantities zero coefficients and overflow" {
  let rate = {
    ..fixed_rate([0], 1L),
    per_row_ms: Some(2L),
    per_wire_byte_ms: Some(3L),
    per_pair_ms: Some(4L),
  }
  let schedule = prepare_rate_schedule(1, [rate], 3).unwrap()
  assert_eq(
    evaluate_rate_schedule(schedule, Some(5L), Some(18L), Some(6L)).unwrap()[0].milliseconds,
    Some(89L),
  )
  assert_eq(
    evaluate_rate_schedule(schedule, Some(5L), Some(18L), None).unwrap()[0].milliseconds,
    None,
  )
  let no_pairs = prepare_rate_schedule(
    1,
    [{ ..rate, per_pair_ms: Some(0L), }],
    3,
  ).unwrap()
  assert_eq(
    evaluate_rate_schedule(no_pairs, Some(5L), Some(18L), None).unwrap()[0].milliseconds,
    Some(65L),
  )
  assert_true(
    evaluate_rate_schedule(
      schedule,
      Some(9223372036854775807L),
      Some(0L),
      Some(0L),
    )
    is Err(Overflow),
  )
  assert_true(
    evaluate_rate_schedule(no_pairs, Some(0L), Some(0L), Some(-1L))
    is Err(InvalidQuantity),
  )
  let missing = prepare_rate_schedule(1, [{ ..rate, per_pair_ms: None, }], 3).unwrap()
  assert_eq(
    evaluate_rate_schedule(missing, Some(0L), Some(0L), Some(0L)).unwrap()[0].milliseconds,
    None,
  )
}

///|
test "rate schedule preparation bounds coverage and rejects invalid coefficients" {
  let rates = [fixed_rate([0, 2], 7L), fixed_rate([1], 11L)]
  assert_true(
    prepare_rate_schedule(3, rates, 7) is Err(Coverage(PlanningLimit)),
  )
  assert_true(prepare_rate_schedule(3, rates, 8) is Ok(_))
  assert_true(
    prepare_rate_schedule(3, [fixed_rate([0, 0], 1L)], 8)
    is Err(Coverage(DuplicateSlot(0))),
  )
  assert_true(
    prepare_rate_schedule(3, [fixed_rate([3], 1L)], 8)
    is Err(Coverage(InvalidSlot(0, 3))),
  )
  assert_true(
    prepare_rate_schedule(3, [fixed_rate([], 1L)], 8)
    is Err(Coverage(EmptyCoverage(0))),
  )
  assert_true(
    prepare_rate_schedule(1, [fixed_rate([0], -1L)], 8)
    is Err(InvalidCoefficient),
  )
  assert_true(prepare_rate_schedule(-1, [], 8) is Err(Coverage(InvalidLimit)))
  let incomplete = prepare_rate_schedule(3, [fixed_rate([0], 1L)], 8).unwrap()
  assert_eq(
    assess_serial(
      3,
      evaluate_rate_schedule(incomplete, None, None, None).unwrap(),
      8,
    ).unwrap(),
    Unknown,
  )
}
