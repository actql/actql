///|
fn binary_scale_budget(maximum : Int) -> ValueBudget {
  value_budget({
    max_nodes: maximum,
    max_text_bytes: maximum,
    max_depth: 10,
    max_work: maximum,
  }).unwrap()
}

///|
fn binary_scale_levels(count : Int) -> Int {
  let mut size = 1
  let mut levels = 0
  while size < count {
    size *= 2
    levels += 1
  }
  levels
}

///|
fn set_scale_owner(operation : String) -> @lower.BoundPrepared {
  bound_pipeline(
    "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"k\":0,\"payload\":0}]},\"as\":\"l\"},{\"values\":{\"schema\":{\"payload\":{\"type\":\"number\",\"nullable\":false},\"k\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"payload\":0,\"k\":0}]},\"as\":\"r\"},{\"from\":\"l\",\"" +
    operation +
    "\":{\"with\":\"r\",\"duplicates\":\"all\"}}]",
  )
}

///|
fn set_scale_sample(operation : String, count : Int) -> (Int, Int) raise {
  let owner = set_scale_owner(operation)
  guard @lower.sequence_step(prepared_sequence(owner), 2)
    is Some(@lower.SetStep(kernel)) else {
    fail("set kernel was not prepared")
  }
  let left_template = table_from_capture(
    capture_values(owner, 0, max_rows=1, run_limits().input_values).unwrap(),
  )
  let right_template = table_from_capture(
    capture_values(owner, 1, max_rows=1, run_limits().input_values).unwrap(),
  )
  let left = {
    ..left_template,
    rows: Array::makei(count, index => {
      [Number(index.to_double()), Number(index.to_double())]
    }),
  }
  let right = {
    ..right_template,
    rows: Array::makei(count, index => {
      let value = index + count / 2
      [Number(value.to_double()), Number(value.to_double())]
    }),
  }
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace = row_workspace(maximum)
  let result = evaluate_set_rows(
    kernel,
    left,
    right,
    count,
    control,
    binary_scale_budget(maximum),
    workspace,
  ).unwrap()
  assert_eq(result.rows.length(), count / 2)
  let first = if operation == "except" { 0 } else { count / 2 }
  assert_true(result.rows[0][0] is Number(value) && value == first.to_double())
  (maximum - control.remaining, workspace.peak)
}

///|
fn cross_join_scale_sample(count : Int) -> (Int, Int) raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":0}]},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"tag\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"tag\":{\"literal\":\"a\"}}]},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"cross_join\":{\"with\":\"right_rows\",\"select\":{\"id\":\"left.id\",\"tag\":\"right.tag\"}}}]",
  )
  guard @lower.sequence_step(prepared_sequence(owner), 2)
    is Some(@lower.CrossJoinStep(kernel)) else {
    fail("cross join kernel was not prepared")
  }
  let left_template = table_from_capture(
    capture_values(owner, 0, max_rows=1, run_limits().input_values).unwrap(),
  )
  let right_template = table_from_capture(
    capture_values(owner, 1, max_rows=1, run_limits().input_values).unwrap(),
  )
  let left = {
    ..left_template,
    rows: Array::makei(count, index => [Number(index.to_double())]),
  }
  let right = {
    ..right_template,
    rows: [[Text("a")], [Text("b")], [Text("c")], [Text("d")]],
  }
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace = row_workspace(maximum)
  let result = evaluate_cross_join_rows(
    kernel,
    left,
    right,
    count * 4,
    control,
    binary_scale_budget(maximum),
    workspace,
  ).unwrap()
  assert_eq(result.rows.length(), count * 4)
  assert_true(result.rows[0][0] is Number(0))
  assert_true(result.rows[0][1] is Text("a"))
  assert_true(result.rows[3][1] is Text("d"))
  (maximum - control.remaining, workspace.peak)
}

///|
test "row set kernels stay within sort-merge scaling floors" {
  for count in [128, 1024, 8192] {
    let levels = binary_scale_levels(count)
    for operation in ["except", "intersect"] {
      let sample = set_scale_sample(operation, count)
      assert_true(sample.0 <= count * (levels * 20 + 100) + 1000)
      assert_true(sample.1 <= count * 8 + 100)
    }
  }
}

///|
test "cross join work and retention follow the emitted product" {
  for count in [128, 1024, 8192] {
    let sample = cross_join_scale_sample(count)
    let output = count * 4
    assert_true(sample.0 <= output * 4 + 100)
    assert_true(sample.1 <= output * 4 + 100)
  }
}

///|
test "equality join uses indexed lookup outside output multiplicity" {
  for count in [128, 1024, 8192] {
    let left = order_table(
      Array::makei(count, index => Number(index.to_double())),
    )
    let right = order_table(
      Array::makei(count, index => Number((count - index - 1).to_double())),
    )
    let maximum = 100000000
    let control = { remaining: maximum, max_frames: 100, }
    let workspace = row_workspace(maximum)
    let pairs = inner_join_indices(
      left,
      right,
      [(0, 0)],
      false,
      count,
      control,
      workspace,
    ).unwrap()
    assert_eq(pairs.length(), count)
    assert_eq(pairs[0], (0, count - 1))
    assert_eq(pairs[count - 1], (count - 1, 0))
    let levels = binary_scale_levels(count)
    let used = maximum - control.remaining
    assert_true(used <= count * (levels * 20 + 50) + 500)
    assert_true(workspace.peak <= count * 4 + 100)
  }
}
