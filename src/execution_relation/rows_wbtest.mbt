///|
fn row_owner(tail : String) -> @lower.BoundPrepared {
  bound_pipeline(
    "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":1,\"b\":0},{\"a\":0,\"b\":1}]},\"as\":\"seed\"}" +
    tail +
    "]",
  )
}

///|
fn row_kernel(
  owner : @lower.BoundPrepared,
  index : Int,
) -> @lower.PreparedKernel {
  @lower.prepare_kernel(owner, index, max_bindings=100, max_name_bytes=1000, {
    max_nodes: 1000,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 1000,
    max_literal_text_bytes: 10000,
  }).unwrap()
}

///|
fn row_capture(owner : @lower.BoundPrepared) -> Table {
  table_from_capture(
    capture_values(owner, 0, max_rows=100, {
      max_nodes: 1000,
      max_text_bytes: 10000,
      max_depth: 100,
      max_work: 10000,
    }).unwrap(),
  )
}

///|
fn row_output() -> ValueBudget {
  value_budget({
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 10000,
  }).unwrap()
}

///|
test "real values derive filter select chain preserves values and authored select order" {
  let owner = row_owner(
    ",{\"derive\":{\"c\":\"a + 10\"}},{\"filter\":\"c > 10\"},{\"select\":[\"c\",\"b\"]}",
  )
  let input = row_capture(owner)
  let control = { remaining: 1000, max_frames: 100, }
  let output = row_output()
  let derived = evaluate_rows(row_kernel(owner, 1), input, 100, control, output).unwrap()
  let filtered = evaluate_rows(
    row_kernel(owner, 2),
    derived,
    100,
    control,
    output,
  ).unwrap()
  let selected = evaluate_rows(
    row_kernel(owner, 3),
    filtered,
    100,
    control,
    output,
  ).unwrap()
  assert_eq(selected.names, ["c", "b"])
  assert_eq(selected.rows.length(), 1)
  assert_true(selected.rows[0][0] is Number(11.0))
  assert_true(selected.rows[0][1] is Number(0.0))
  assert_eq(input.names, ["a", "b"])
  assert_eq(input.rows.length(), 2)
  assert_true(input.rows[0][0] is Number(1.0))
}

///|
test "map failures are row then canonical binding order including unused RHS" {
  let owner = row_owner(
    ",{\"derive\":{\"y\":\"1 / b\",\"x\":\"1 / a\"}},{\"select\":[\"a\"]}",
  )
  guard evaluate_rows(
      row_kernel(owner, 1),
      row_capture(owner),
      100,
      { remaining: 1000, max_frames: 100, },
      row_output(),
    )
    is Err(Evaluation(0, 1, issue)) else {
    fail("must fail row zero second binding, not row one first binding")
  }
  assert_eq(issue.kind, Scalar(ArithmeticFailure))
}

///|
test "kernel rejects foreign owner and wrong branch before row evaluation" {
  let owner = row_owner(",{\"derive\":{}},{\"select\":[\"a\"]}")
  let input = row_capture(owner)
  let control = { remaining: 1000, max_frames: 100, }
  assert_true(
    evaluate_rows(row_kernel(owner, 2), input, 100, control, row_output())
    is Err(InputMismatch),
  )
  let foreign = row_owner(",{\"derive\":{}},{\"select\":[\"a\"]}")
  assert_true(
    evaluate_rows(row_kernel(foreign, 1), input, 100, control, row_output())
    is Err(OwnerMismatch),
  )
  assert_eq(control.remaining, 1000)
  let identity = evaluate_rows(
    row_kernel(owner, 1),
    input,
    100,
    control,
    row_output(),
  ).unwrap()
  assert_eq(identity.names, input.names)
  assert_eq(identity.rows.length(), input.rows.length())
  assert_eq(identity.id, "derive_1")
}

///|
test "derived retained output is measured before later projection and failure is atomic" {
  let owner = row_owner(",{\"derive\":{\"c\":\"a + 1\"}},{\"select\":[\"c\"]}")
  let input = row_capture(owner)
  let insufficient = value_budget({
    max_nodes: 7,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 100,
  }).unwrap()
  assert_true(
    evaluate_rows(
      row_kernel(owner, 1),
      input,
      100,
      { remaining: 1000, max_frames: 100, },
      insufficient,
    )
    is Err(RowLimit),
  )
  // Both logical derive rows contain a,b,c: eight nodes, not four selected nodes.
  let exact = value_budget({
    max_nodes: 8,
    max_text_bytes: 6,
    max_depth: 2,
    max_work: 14,
  }).unwrap()
  let result = evaluate_rows(
    row_kernel(owner, 1),
    input,
    100,
    { remaining: 1000, max_frames: 100, },
    exact,
  ).unwrap()
  assert_eq(result.rows.length(), 2)
  assert_eq(exact.nodes, 8)
  assert_true(result.rows[1][2] is Number(1.0))
}
