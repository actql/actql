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
test "explicit supplied input runs map filter select with the same owner and budgets" {
  let seed = row_capture(row_owner(""))
  // Obtain the schema from checked values, not inferred from supplied rows.
  let captured = capture_values(seed.owner, 0, max_rows=2, {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 200,
  }).unwrap()
  let checked = @pipeline.check(
    input_cursor(
      "[{\"derive\":{\"c\":\"a + 10\"}},{\"filter\":\"c > 10\"},{\"select\":[\"c\",\"b\"]}]",
    ),
    [("source", captured_schema(captured))],
    None,
    Some(input_cursor("\"source\"")),
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let input = table_from_capture(
    capture_input(
      owner,
      0,
      [input_cursor("{\"a\":1,\"b\":0}"), input_cursor("{\"a\":0,\"b\":1}")],
      max_rows=2,
      { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
    ).unwrap(),
  )
  let control = { remaining: 1000, max_frames: 100, }
  let output = row_output()
  let a = evaluate_rows(row_kernel(owner, 0), input, 2, control, output).unwrap()
  let b = evaluate_rows(row_kernel(owner, 1), a, 2, control, output).unwrap()
  let c = evaluate_rows(row_kernel(owner, 2), b, 2, control, output).unwrap()
  assert_eq(c.names, ["c", "b"])
  assert_eq(c.rows.length(), 1)
  assert_true(c.rows[0][0] is Number(11.0))
  assert_true(c.rows[0][1] is Number(0.0))
}

///|
test "branch target skips previous producer and cumulative output cannot reset between kernels" {
  let owner = row_owner(
    ",{\"derive\":{\"c\":\"a + 1\"},\"as\":\"augmented\"},{\"filter\":\"a > 10\"},{\"from\":\"augmented\",\"select\":[\"c\"]}",
  )
  let control = { remaining: 1000, max_frames: 100, }
  let output = value_budget({
    max_nodes: 12,
    max_text_bytes: 8,
    max_depth: 2,
    max_work: 20,
  }).unwrap()
  let derived = evaluate_rows(
    row_kernel(owner, 1),
    row_capture(owner),
    2,
    control,
    output,
  ).unwrap()
  let empty = evaluate_rows(row_kernel(owner, 2), derived, 2, control, output).unwrap()
  assert_eq(empty.rows.length(), 0)
  assert_true(
    evaluate_rows(row_kernel(owner, 3), empty, 2, control, output)
    is Err(InputMismatch),
  )
  let selected = evaluate_rows(
    row_kernel(owner, 3),
    derived,
    2,
    control,
    output,
  ).unwrap()
  assert_eq(selected.rows.length(), 2)
  assert_eq(output.nodes, 12)
  assert_eq(output.work, 20)
  let short = value_budget({
    max_nodes: 11,
    max_text_bytes: 8,
    max_depth: 2,
    max_work: 20,
  }).unwrap()
  let control2 = { remaining: 1000, max_frames: 100, }
  let again = evaluate_rows(
    row_kernel(owner, 1),
    row_capture(owner),
    2,
    control2,
    short,
  ).unwrap()
  assert_true(
    evaluate_rows(row_kernel(owner, 3), again, 2, control2, short)
    is Err(RowLimit),
  )
}

///|
test "row setup consumes work even with empty input; projection skips snapshot allocation" {
  let owner = row_owner(",{\"select\":[\"b\",\"a\"]}")
  let input = row_capture(owner)
  let empty = { ..input, rows: [], }
  // Two input names: 2 * (entry + byte), two projection entries:
  // 2 * (entry + input-name byte + output-name byte), plus two copied kernel
  // entries = twelve setup units.
  let exact = { remaining: 12, max_frames: 0, }
  assert_eq(
    evaluate_rows(row_kernel(owner, 1), empty, 0, exact, row_output()).unwrap().rows.length(),
    0,
  )
  assert_eq(exact.remaining, 0)
  assert_true(
    evaluate_rows(
      row_kernel(owner, 1),
      empty,
      0,
      { remaining: 11, max_frames: 0, },
      row_output(),
    )
    is Err(RowLimit),
  )
  // Two rows each require one visit and two ordinal copies; no snapshot map.
  let full = { remaining: 18, max_frames: 0, }
  assert_eq(
    evaluate_rows(row_kernel(owner, 1), input, 2, full, row_output()).unwrap().rows.length(),
    2,
  )
  assert_eq(full.remaining, 0)
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
