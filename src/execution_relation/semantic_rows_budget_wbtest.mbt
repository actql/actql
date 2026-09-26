///|
test "vector comparison charges every compared dimension before traversal" {
  guard runtime_vector([1.0, 2.0, 3.0]) is Captured(left) else {
    fail("left vector")
  }
  guard runtime_vector([1.0, 2.0, 3.0]) is Captured(right) else {
    fail("right vector")
  }
  let exact = { remaining: 4, max_frames: 1, }
  assert_true(compare_admitted_value(left, right, exact) is Ok(0))
  assert_eq(exact.remaining, 0)

  let short = { remaining: 3, max_frames: 1, }
  assert_true(compare_admitted_value(left, right, short) is Err(Limit))
  // The outer value comparison is charged, but the all-or-nothing vector
  // dimension charge is rejected before traversal.
  assert_eq(short.remaining, 2)
}

///|
test "plain Text admission charges UTF-8 work before normalization" {
  let value = Text("é日😀")
  let exact = { remaining: 9, max_frames: 1, }
  assert_true(admitted_nest_value(value, exact) is Ok(@admitted.Text(_)))
  assert_eq(exact.remaining, 0)

  let short = { remaining: 8, max_frames: 1, }
  assert_true(admitted_nest_value(value, short) is Err(RowLimit))
  assert_eq(short.remaining, 8)

  let aggregate = { remaining: 9, max_frames: 1, }
  assert_true(
    admitted_aggregate_item(value, aggregate) is Ok(Some(@admitted.Text(_))),
  )
  assert_eq(aggregate.remaining, 0)
}

///|
test "timestamp work exhaustion remains a canonical resource error" {
  assert_true(window_time_row_issue(WindowTimeResourceLimit, 7) is RowLimit)
  assert_true(window_time_row_issue(InvalidWindowTime, 7) is WindowTime(7))
}

///|
test "bounded complete text comparison retains exact work and UTF-16 order" {
  let left = Text("x".repeat(128) + "\u{e000}")
  let right = Text("x".repeat(128) + "\u{10000}")
  let exact : ControlBudget = { remaining: 264, max_frames: 1, }
  let cursor = bounded_complete_value_comparison()
  let mut result : Int? = None
  let mut steps = 0
  while result is None && steps < 800 {
    steps += 1
    match bounded_complete_value_comparison_step(cursor, left, right, exact) {
      Ok(Some(value)) => result = Some(value)
      Ok(None) => ()
      Err(_) => fail("exact comparison rejected")
    }
  }
  assert_eq(result, Some(1))
  assert_true(steps > 256)
  assert_eq(exact.remaining, 0)
  assert_eq(cursor.phase, -1)

  let short : ControlBudget = { remaining: 263, max_frames: 1, }
  let short_cursor = bounded_complete_value_comparison()
  let mut exhausted = false
  for _ in 0..<800 {
    if exhausted {
      break
    }
    match
      bounded_complete_value_comparison_step(short_cursor, left, right, short) {
      Ok(None) => ()
      Err(Limit) => exhausted = true
      _ => fail("one-short comparison was accepted")
    }
  }
  assert_true(exhausted)
  assert_eq(short.remaining, 3)
}
