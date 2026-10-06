///|
fn step_collection_limits() -> ValueLimits {
  { max_nodes: 1000, max_text_bytes: 100000, max_depth: 16, max_work: 100000, }
}

///|
fn[T] drain_counting(
  advance : () -> Result[T?, RowIssue],
  control : ControlBudget,
) -> (Result[T, RowIssue], Bool, Int) {
  let mut at_most_one = true
  let mut advances = 0
  while true {
    advances += 1
    let before = control.remaining
    let step = advance()
    if before - control.remaining > 1 {
      at_most_one = false
    }
    match step {
      Ok(None) => ()
      Ok(Some(value)) => break (Ok(value), at_most_one, advances)
      Err(issue) => break (Err(issue), at_most_one, advances)
    }
  } nobreak {
    (Err(InvalidRows), at_most_one, advances)
  }
}

///|
fn texts(values : Array[Value]) -> Array[String] {
  values.map(value => {
    match value {
      Text(text) => text
      Number(number) => "n" + number.to_string()
      Null => "null"
      _ => "other"
    }
  })
}

///|
test "distinct steps match the atomic distinct in values, charge and space" {
  let long = "é".repeat(30)
  let values : Array[Value] = [
    Text(long),
    Number(1),
    Text(long),
    Text("x"),
    Number(1),
    Text(long + "y"),
    Text("x"),
  ]
  let reference : ControlBudget = { remaining: 100000, max_frames: 0, }
  let reference_space = { limit: 10000, live: 0, peak: 0, }
  let expected = atomic_distinct_aggregate_values(
    values,
    reference,
    reference_space,
    step_collection_limits(),
  ).unwrap()
  let control : ControlBudget = { remaining: 100000, max_frames: 0, }
  let space = { limit: 10000, live: 0, peak: 0, }
  let state = start_aggregate_distinct(
    values,
    control,
    space,
    step_collection_limits(),
  )
  let (actual, at_most_one, _) = drain_counting(
    () => advance_aggregate_distinct(state),
    control,
  )
  assert_eq(texts(actual.unwrap()), texts(expected))
  assert_eq(texts(expected).length(), 4)
  assert_eq(control.remaining, reference.remaining)
  assert_eq(space.peak, reference_space.peak)
  assert_eq(space.live, reference_space.live)
  assert_true(at_most_one)
  let charge = 100000 - reference.remaining
  let short : ControlBudget = { remaining: charge - 1, max_frames: 0, }
  let failing = start_aggregate_distinct(
    values,
    short,
    { limit: 10000, live: 0, peak: 0, },
    step_collection_limits(),
  )
  let (failed, _, _) = drain_counting(
    () => advance_aggregate_distinct(failing),
    short,
  )
  assert_true(failed is Err(RowLimit))
}

///|
test "ordered value steps match the atomic collection" {
  let table = order_table([Number(3), Null, Number(1), Number(2)])
  let range : AggregateGroupRange = {
    representative: Some(0),
    start: 0,
    end: 4,
  }
  let order = [{ column: 1, descending: true, nulls_first: true, }]
  let reference : ControlBudget = { remaining: 1000, max_frames: 0, }
  let reference_space = { limit: 100, live: 0, peak: 0, }
  let expected = atomic_ordered_aggregate_values(
    table,
    [0, 1, 2, 3],
    range,
    0,
    order,
    reference,
    reference_space,
  ).unwrap()
  let control : ControlBudget = { remaining: 1000, max_frames: 0, }
  let space = { limit: 100, live: 0, peak: 0, }
  let state = start_aggregate_ordered_values(
    { input: table, indices: [0, 1, 2, 3], start: 0, end: 4, },
    order,
    0,
    control,
    space,
  )
  let (actual, at_most_one, _) = drain_counting(
    () => advance_aggregate_ordered_values(state),
    control,
  )
  assert_eq(texts(actual.unwrap()), texts(expected))
  assert_eq(texts(expected), ["n2", "n1", "n3"])
  assert_eq(control.remaining, reference.remaining)
  assert_eq(space.peak, reference_space.peak)
  assert_true(at_most_one)
}

///|
test "array steps charge one unit per item and row Text bytes" {
  let values : Array[Value] = [
    Text("é𐀀"),
    Number(2),
    Boolean(true),
    Text(""),
  ]
  // Four items, then "é𐀀" is 2 + 4 UTF-8 bytes.
  let charge = 4 + 6
  let exact : ControlBudget = { remaining: charge, max_frames: 0, }
  let space = { limit: 100, live: 0, peak: 0, }
  let state = start_aggregate_array(values, exact, space)
  let (value, at_most_one, _) = drain_counting(
    () => advance_aggregate_array(state),
    exact,
  )
  assert_true(value is Ok(Captured(_)))
  assert_eq(exact.remaining, 0)
  assert_true(at_most_one)
  assert_eq(space.live, 4)
  let short : ControlBudget = { remaining: charge - 1, max_frames: 0, }
  let failing = start_aggregate_array(values, short, {
    limit: 100,
    live: 0,
    peak: 0,
  })
  let (failed, _, _) = drain_counting(
    () => advance_aggregate_array(failing),
    short,
  )
  assert_true(failed is Err(RowLimit))
  let nulls = start_aggregate_array(
    [Number(1), Null],
    { remaining: 100, max_frames: 0, },
    { limit: 100, live: 0, peak: 0, },
  )
  let (rejected, _, _) = drain_counting(() => advance_aggregate_array(nulls), {
    remaining: 100,
    max_frames: 0,
  })
  assert_true(rejected is Err(InvalidRows))
}

///|
test "string steps charge separators and item bytes and honor the maximum" {
  let values : Array[Value] = [Text("ab"), Text("é"), Text("c")]
  // Items 2 + 2 + 1 bytes and two ", " separators of 2 bytes.
  let charge = 5 + 4
  let exact : ControlBudget = { remaining: charge, max_frames: 0, }
  let state = start_aggregate_string(
    values,
    ", ",
    100L,
    exact,
    row_workspace(100),
  ).unwrap()
  let (value, at_most_one, _) = drain_counting(
    () => advance_aggregate_string(state),
    exact,
  )
  guard value is Ok(Text(text)) else { fail("string aggregate failed") }
  assert_eq(text, "ab, é, c")
  assert_eq(exact.remaining, 0)
  assert_true(at_most_one)
  let short : ControlBudget = { remaining: charge - 1, max_frames: 0, }
  let failing = start_aggregate_string(
    values,
    ", ",
    100L,
    short,
    row_workspace(100),
  ).unwrap()
  let (failed, _, _) = drain_counting(
    () => advance_aggregate_string(failing),
    short,
  )
  assert_true(failed is Err(RowLimit))
  let capped : ControlBudget = { remaining: 100, max_frames: 0, }
  let over = start_aggregate_string(
    values,
    ", ",
    8L,
    capped,
    row_workspace(100),
  ).unwrap()
  let (limited, _, _) = drain_counting(
    () => advance_aggregate_string(over),
    capped,
  )
  assert_true(limited is Err(RowLimit))
}
