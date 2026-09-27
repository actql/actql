///|
fn sum_decimal(coefficient : String) -> Value {
  Captured(@admitted.decimal_from_coefficient(coefficient, 38, 2).unwrap())
}

///|
/// Reference fold with the atomic coefficient addition used before the step
/// form.
fn atomic_decimal_sum(
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[String, RowIssue] {
  let mut coefficient = "0"
  for value in values {
    guard value is Captured(@admitted.Decimal(decimal)) else {
      return Err(InvalidRows)
    }
    coefficient = match
      add_decimal_coefficients(
        coefficient,
        decimal.coefficient,
        control,
        workspace,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  Ok(coefficient)
}

///|
fn drain_decimal_sum(
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> (Result[Value, RowIssue], Bool) {
  let state = start_aggregate_decimal_sum(values, 38, 2, control, workspace)
  let mut at_most_one = true
  while true {
    let before = control.remaining
    let step = advance_aggregate_decimal_sum(state)
    if before - control.remaining > 1 {
      at_most_one = false
    }
    match step {
      Ok(None) => ()
      Ok(Some(value)) => break (Ok(value), at_most_one)
      Err(issue) => break (Err(issue), at_most_one)
    }
  } nobreak {
    (Err(InvalidRows), at_most_one)
  }
}

///|
test "decimal sum steps match the atomic fold in value and charge" {
  let values = [
    sum_decimal("12345678901234567890"),
    sum_decimal("-99999"),
    sum_decimal("1"),
    sum_decimal("-12345678901234567890"),
    sum_decimal("99999"),
    sum_decimal("250"),
  ]
  let reference : ControlBudget = { remaining: 100000, max_frames: 0, }
  let reference_space = { limit: 1000, live: 0, peak: 0, }
  let expected = atomic_decimal_sum(values, reference, reference_space).unwrap()
  let stepped : ControlBudget = { remaining: 100000, max_frames: 0, }
  let space = { limit: 1000, live: 0, peak: 0, }
  let (actual, at_most_one) = drain_decimal_sum(values, stepped, space)
  guard actual is Ok(Captured(@admitted.Decimal(decimal))) else {
    fail("decimal sum failed")
  }
  assert_eq(decimal.coefficient, expected)
  assert_eq(decimal.coefficient, "251")
  assert_eq(stepped.remaining, reference.remaining)
  assert_true(at_most_one)
  assert_eq(space.live, 0)
  assert_eq(space.peak, reference_space.peak)
  // One unit short fails without publishing a value.
  let charge = 100000 - reference.remaining
  let short : ControlBudget = { remaining: charge - 1, max_frames: 0, }
  let (failed, _) = drain_decimal_sum(values, short, {
    limit: 1000,
    live: 0,
    peak: 0,
  })
  assert_true(failed is Err(RowLimit))
  let exact : ControlBudget = { remaining: charge, max_frames: 0, }
  let (succeeded, _) = drain_decimal_sum(values, exact, {
    limit: 1000,
    live: 0,
    peak: 0,
  })
  assert_true(succeeded is Ok(_))
  assert_eq(exact.remaining, 0)
}

///|
test "decimal sum steps reject a foreign contributor scale" {
  let values = [
    sum_decimal("1"),
    Captured(@admitted.decimal_from_coefficient("1", 38, 3).unwrap()),
  ]
  let control : ControlBudget = { remaining: 100000, max_frames: 0, }
  let (result, _) = drain_decimal_sum(values, control, {
    limit: 1000,
    live: 0,
    peak: 0,
  })
  assert_true(result is Err(InvalidRows))
}

///|
test "endpoint steps return the first and last non-null member" {
  let table = order_table([Number(3), Number(1), Number(2), Number(4)])
  let members : AggregateRangeRows[Table] = {
    input: table,
    indices: [0, 1, 2, 3],
    start: 0,
    end: 4,
  }
  let order = [{ column: 0, descending: false, nulls_first: true, }]
  for first in [true, false] {
    let control : ControlBudget = { remaining: 1000, max_frames: 0, }
    let workspace = { limit: 100, live: 0, peak: 0, }
    let state = start_aggregate_endpoint(
      members, order, 1, first, control, workspace,
    )
    let mut result = None
    let mut polls = 0
    while result is None {
      polls += 1
      let before = control.remaining
      match advance_aggregate_endpoint(state) {
        Ok(None) => ()
        Ok(Some(value)) => result = Some(value)
        Err(_) => fail("endpoint failed")
      }
      assert_true(before - control.remaining <= 1)
    }
    // Payload column holds the source row position: key 1 is row 1 and
    // key 4 is row 3.
    guard result is Some(Number(position)) else { fail("no endpoint") }
    assert_eq(position, if first { 1.0 } else { 3.0 })
    assert_true(polls > 4)
  }
}
