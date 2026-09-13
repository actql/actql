///|
fn estimate(slots : Array[Int], duration : Int64?) -> SerialEstimateLine {
  { work_slots: slots, milliseconds: duration, }
}

///|
test "physical serial cost counts transfer conversion capture retention and cleanup" {
  // Independent fixture: native acquisition 3, transfer 2, conversion 1,
  // capture 2, required holding work 1, downstream compute 4, cleanup 1.
  let native = assess_serial(
    7,
    [
      estimate([0], Some(3L)),
      estimate([1], Some(2L)),
      estimate([2], Some(1L)),
      estimate([3], Some(2L)),
      estimate([4], Some(1L)),
      estimate([5], Some(4L)),
      estimate([6], Some(1L)),
    ],
    21,
  ).unwrap()
  // Broad acquisition bundles reading + transfer + conversion into 10;
  // residual 6, capture 2, holding 2, consumer 4, cleanup 1.
  let broad = assess_serial(
    8,
    [
      estimate([0, 1, 2], Some(10L)),
      estimate([3], Some(6L)),
      estimate([4], Some(2L)),
      estimate([5], Some(2L)),
      estimate([6], Some(4L)),
      estimate([7], Some(1L)),
    ],
    22,
  ).unwrap()
  assert_eq(native, Complete(14L))
  assert_eq(broad, Complete(25L))
  assert_eq(
    choose_serial([native, broad], None, 2),
    Ok(EstimatedFastest(0, 14L)),
  )
  assert_eq(
    choose_serial([Complete(30L), broad], None, 2),
    Ok(EstimatedFastest(1, 25L)),
  )
}

///|
test "composite breakdown and repeated transfer cannot be double counted" {
  assert_eq(
    assess_serial(2, [estimate([0, 1], Some(9L)), estimate([1], Some(3L))], 7),
    Err(DuplicateSlot(1)),
  )
  assert_eq(
    assess_serial(1, [estimate([0, 0], Some(9L))], 4),
    Err(DuplicateSlot(0)),
  )
  assert_eq(assess_serial(2, [estimate([0, 1], Some(9L))], 5), Ok(Complete(9L)))
}

///|
test "missing retained work and missing estimates are unknown" {
  assert_eq(assess_serial(2, [estimate([0], Some(1L))], 4), Ok(Unknown))
  assert_eq(assess_serial(1, [estimate([0], None)], 3), Ok(Unknown))
  assert_eq(
    assess_serial(2, [estimate([0], None), estimate([1], Some(-1L))], 6),
    Err(NegativeDuration(1)),
  )
  assert_eq(choose_serial([Complete(1L), Unknown], None, 2), Ok(Deferred))
  assert_eq(
    choose_serial([Complete(1L), Unknown], Some([1, 0]), 4),
    Ok(HostPreferred(1)),
  )
  assert_eq(
    choose_serial([Complete(1L), Unknown], Some([0, 1]), 4),
    Ok(HostPreferred(0)),
  )
}

///|
test "invalid estimate is distinct from missing knowledge" {
  assert_eq(
    assess_serial(1, [estimate([], Some(0L))], 2),
    Err(EmptyCoverage(0)),
  )
  assert_eq(
    assess_serial(1, [estimate([1], Some(0L))], 3),
    Err(InvalidSlot(0, 1)),
  )
  assert_eq(
    assess_serial(1, [estimate([-1], Some(0L))], 3),
    Err(InvalidSlot(0, -1)),
  )
  assert_eq(
    assess_serial(1, [estimate([0], Some(-1L))], 3),
    Err(NegativeDuration(0)),
  )
  assert_eq(
    assess_serial(
      2,
      [estimate([0], Some(9223372036854775807L)), estimate([1], Some(1L))],
      6,
    ),
    Err(DurationOverflow),
  )
  assert_eq(choose_serial([Complete(-1L)], None, 1), Err(NegativeDuration(0)))
}

///|
test "planning boundaries precede allocation and preserve inputs" {
  let slots = [0, 1]
  let lines = [estimate(slots, Some(7L))]
  assert_eq(assess_serial(2, lines, 4), Err(PlanningLimit))
  assert_eq(assess_serial(2, lines, 5), Ok(Complete(7L)))
  assert_eq(assess_serial(2, lines, 5), Ok(Complete(7L)))
  assert_eq(slots, [0, 1])
  assert_eq(assess_serial(-1, lines, 5), Err(InvalidLimit))
  assert_eq(assess_serial(0, [], -1), Err(InvalidLimit))
  assert_eq(assess_serial(2147483647, [], 0), Err(PlanningLimit))
  assert_eq(choose_serial([Unknown], Some([0]), 1), Err(PlanningLimit))
  assert_eq(choose_serial([Unknown], Some([0]), 2), Ok(HostPreferred(0)))
  assert_eq(choose_serial([], None, -1), Err(InvalidLimit))
}

///|
test "priority is explicit complete and cannot inject a candidate" {
  assert_eq(
    choose_serial([Unknown, Unknown], Some([0, 0]), 4),
    Err(InvalidPreference),
  )
  assert_eq(choose_serial([Unknown], Some([1]), 2), Err(InvalidPreference))
  assert_eq(choose_serial([Unknown], Some([-1]), 2), Err(InvalidPreference))
  assert_eq(
    choose_serial([Unknown, Unknown], Some([0]), 3),
    Err(InvalidPreference),
  )
  assert_eq(choose_serial([Unknown], Some([]), 1), Err(InvalidPreference))
  assert_eq(
    choose_serial([Complete(2L), Complete(1L)], Some([0, 1]), 4),
    Ok(EstimatedFastest(1, 1L)),
  )
}

///|
test "empty work zero and exact maximum have defined meanings" {
  assert_eq(assess_serial(0, [], 0), Ok(Complete(0L)))
  assert_eq(choose_serial([], Some([]), 0), Ok(NoCandidates))
  assert_eq(
    choose_serial([Complete(0L), Complete(0L)], None, 2),
    Ok(EstimatedFastest(0, 0L)),
  )
  assert_eq(
    choose_serial([Complete(9223372036854775807L)], None, 1),
    Ok(EstimatedFastest(0, 9223372036854775807L)),
  )
}
