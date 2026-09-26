///|
fn drain_value_steps(
  advance : () -> Result[Value?, RowIssue],
  control : ControlBudget,
) -> (Result[Value, RowIssue], Bool) {
  let mut at_most_one = true
  while true {
    let before = control.remaining
    let step = advance()
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
fn stats_limits() -> ValueLimits {
  { max_nodes: 1000, max_text_bytes: 100000, max_depth: 16, max_work: 100000, }
}

///|
test "merge sort steps order like the atomic complete-value sort" {
  let long = "é".repeat(20)
  let values : Array[Value] = [
    Text(long + "b"),
    Number(3),
    Null,
    Text(long + "a"),
    Number(-1),
    Boolean(true),
    Number(3),
    Text(""),
  ]
  let reference = values.copy()
  atomic_sort_aggregate_values(
    reference,
    { remaining: 100000, max_frames: 0, },
    { limit: 100, live: 0, peak: 0, },
  ).unwrap()
  let control : ControlBudget = { remaining: 100000, max_frames: 0, }
  let sort = start_aggregate_merge_sort(
    values,
    complete_value_step_comparator(control),
  )
  let mut sorted = None
  while sorted is None {
    let before = control.remaining
    match advance_aggregate_merge_sort(sort) {
      Ok(None) => ()
      Ok(Some(value)) => sorted = Some(value)
      Err(_) => fail("merge sort failed")
    }
    assert_true(before - control.remaining <= 1)
  }
  assert_eq(texts(sorted.unwrap()), texts(reference))
}

///|
test "percentile steps pick ranks and interpolate within exact limits" {
  let values : Array[Value] = [Number(40), Number(10), Number(30), Number(20)]
  for
    case in [
      (0.5, true, 20.0),
      (0.75, true, 30.0),
      (0.5, false, 25.0),
      (1.0, false, 40.0),
    ] {
    let (fraction, discrete, expected) = case
    let probe : ControlBudget = { remaining: 100000, max_frames: 0, }
    let (value, at_most_one) = {
      let state = start_aggregate_percentile(
        values,
        fraction,
        discrete,
        probe,
        { limit: 100, live: 0, peak: 0, },
      )
      drain_value_steps(() => advance_aggregate_percentile(state), probe)
    }
    assert_true(value is Ok(Number(number)) && number == expected)
    assert_true(at_most_one)
    let charge = 100000 - probe.remaining
    let exact : ControlBudget = { remaining: charge, max_frames: 0, }
    let state = start_aggregate_percentile(values, fraction, discrete, exact, {
      limit: 100,
      live: 0,
      peak: 0,
    })
    let (again, _) = drain_value_steps(
      () => advance_aggregate_percentile(state),
      exact,
    )
    assert_true(again is Ok(_))
    assert_eq(exact.remaining, 0)
    let short : ControlBudget = { remaining: charge - 1, max_frames: 0, }
    let failing = start_aggregate_percentile(
      values,
      fraction,
      discrete,
      short,
      { limit: 100, live: 0, peak: 0, },
    )
    let (failed, _) = drain_value_steps(
      () => advance_aggregate_percentile(failing),
      short,
    )
    assert_true(failed is Err(RowLimit))
  }
}

///|
test "statistical steps follow canonical identity order and exact limits" {
  let values : Array[Value] = [
    Number(2),
    Number(4),
    Number(4),
    Number(4),
    Number(5),
    Number(5),
    Number(7),
    Number(9),
  ]
  let reference = atomic_canonical_numeric_values(
    values,
    { remaining: 100000, max_frames: 0, },
    { limit: 1000, live: 0, peak: 0, },
    stats_limits(),
  ).unwrap()
  for
    case in [(false, false, 4.0), (false, true, 2.0), (true, false, 32.0 / 7.0)] {
    let (sample, deviation, expected) = case
    let probe : ControlBudget = { remaining: 100000, max_frames: 0, }
    let state = start_aggregate_statistical(
      values,
      sample,
      deviation,
      probe,
      { limit: 1000, live: 0, peak: 0, },
      stats_limits(),
    )
    let (value, at_most_one) = drain_value_steps(
      () => advance_aggregate_statistical(state),
      probe,
    )
    assert_true(value is Ok(Number(number)) && number == expected)
    assert_true(at_most_one)
    assert_eq(state.numbers, reference)
    let charge = 100000 - probe.remaining
    let short : ControlBudget = { remaining: charge - 1, max_frames: 0, }
    let failing = start_aggregate_statistical(
      values,
      sample,
      deviation,
      short,
      { limit: 1000, live: 0, peak: 0, },
      stats_limits(),
    )
    let (failed, _) = drain_value_steps(
      () => advance_aggregate_statistical(failing),
      short,
    )
    assert_true(failed is Err(RowLimit))
  }
}
