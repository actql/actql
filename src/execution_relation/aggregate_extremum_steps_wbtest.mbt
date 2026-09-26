///|
/// Reference fold with the atomic comparator used before the step form.
fn atomic_extremum(
  values : Array[Value],
  minimum : Bool,
  control : ControlBudget,
) -> Result[Value, RowIssue] {
  if values.is_empty() {
    return Ok(Null)
  }
  let mut selected = values[0]
  for i = 1; i < values.length(); i = i + 1 {
    let comparison = match
      compare_complete_value(values[i], selected, control) {
      Ok(value) => value
      Err(issue) => return Err(ordering_row_issue(issue))
    }
    if (minimum && comparison < 0) || (!minimum && comparison > 0) {
      selected = values[i]
    }
  }
  Ok(selected)
}

///|
fn drain_extremum(
  values : Array[Value],
  minimum : Bool,
  control : ControlBudget,
) -> (Result[Value, RowIssue], Int) raise {
  let state = start_aggregate_extremum(values, minimum, control)
  let mut advances = 0
  while true {
    advances += 1
    let before = control.remaining
    let step = advance_aggregate_extremum(state)
    assert_true(before - control.remaining <= 1)
    match step {
      Ok(None) => ()
      Ok(Some(value)) => break (Ok(value), advances)
      Err(issue) => break (Err(issue), advances)
    }
  } nobreak {
    (Err(InvalidRows), advances)
  }
}

///|
test "extremum steps match the atomic fold in value and charge" {
  let long = "é".repeat(40)
  let cases : Array[Array[Value]] = [
    [],
    [Number(3), Number(-1), Number(7), Null, Number(7)],
    [
      Text(long + "b"),
      Text(long + "a"),
      Text(long + "c"),
      Text("𐀀"),
      Text(""),
    ],
    [Boolean(true), Boolean(false), Null],
  ]
  for values in cases {
    for minimum in [true, false] {
      let reference : ControlBudget = { remaining: 100000, max_frames: 0, }
      let stepped : ControlBudget = { remaining: 100000, max_frames: 0, }
      let expected = atomic_extremum(values, minimum, reference)
      let (actual, _) = drain_extremum(values, minimum, stepped)
      match (actual, expected) {
        (Ok(Text(a)), Ok(Text(b))) => assert_eq(a, b)
        (Ok(Number(a)), Ok(Number(b))) => assert_eq(a, b)
        (Ok(Boolean(a)), Ok(Boolean(b))) => assert_eq(a, b)
        (Ok(Null), Ok(Null)) => ()
        _ => fail("extremum steps selected a different value")
      }
      assert_eq(stepped.remaining, reference.remaining)
    }
  }
}

///|
test "extremum steps split long equal text prefixes and fail one short" {
  let long = "é".repeat(40)
  let values : Array[Value] = [Text(long + "b"), Text(long + "a")]
  let reference : ControlBudget = { remaining: 100000, max_frames: 0, }
  let _ = atomic_extremum(values, true, reference)
  let charge = 100000 - reference.remaining
  let exact : ControlBudget = { remaining: charge, max_frames: 0, }
  let (result, advances) = drain_extremum(values, true, exact)
  assert_true(result is Ok(Text(_)))
  assert_eq(exact.remaining, 0)
  // A long equal prefix is compared across many bounded advances.
  assert_true(advances > 40)
  let short : ControlBudget = { remaining: charge - 1, max_frames: 0, }
  let (failed, _) = drain_extremum(values, true, short)
  assert_true(failed is Err(RowLimit))
}
