///|
fn table_from_capture(input : CapturedRows) -> Table {
  table_from_capture_bounded(input, { remaining: 100000, max_frames: 0, }, {
    limit: 100000,
    live: 0,
    peak: 0,
  }).unwrap()
}

///|
// Test convenience only: delegates to the sole production row evaluator with
// an explicit generous workspace ceiling. No alternate execution semantics.
fn evaluate_rows(
  kernel : @lower.PreparedKernel,
  input : Table,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
) -> Result[Table, RowIssue] {
  evaluate_rows_with_workspace(kernel, input, max_rows, control, output, {
    limit: 100000,
    live: 0,
    peak: 0,
  })
}

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
test "row assertions preserve exact rows and fail atomically" {
  let owner = row_owner(
    ",{\"assert_rows\":{\"where\":\"a >= 0\"}},{\"assert_rows\":{\"unique_by\":[\"a\"]}}",
  )
  let input = row_capture(owner)
  let asserted = evaluate_rows(
    row_kernel(owner, 1),
    input,
    2,
    { remaining: 10000, max_frames: 100, },
    row_output(),
  ).unwrap()
  assert_eq(asserted.names, ["a", "b"])
  assert_true(asserted.rows[0][0] is Number(1.0))
  assert_true(asserted.rows[1][0] is Number(0.0))
  let unique = evaluate_rows(
    row_kernel(owner, 2),
    asserted,
    2,
    { remaining: 10000, max_frames: 100, },
    row_output(),
  ).unwrap()
  assert_eq(unique.rows.length(), 2)

  let predicate_failure = row_owner(",{\"assert_rows\":{\"where\":\"a > 0\"}}")
  assert_true(
    evaluate_rows(
      row_kernel(predicate_failure, 1),
      row_capture(predicate_failure),
      2,
      { remaining: 10000, max_frames: 100, },
      row_output(),
    )
    is Err(AssertionPredicate(1)),
  )

  let duplicate = bound_pipeline(
    "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":1},{\"a\":1}]},\"as\":\"seed\"},{\"assert_rows\":{\"unique_by\":[\"a\"]}}]",
  )
  assert_true(
    evaluate_rows(
      row_kernel(duplicate, 1),
      row_capture(duplicate),
      2,
      { remaining: 10000, max_frames: 100, },
      row_output(),
    )
    is Err(AssertionDuplicate(0, 1)),
  )

  let nullable = bound_pipeline(
    "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"a\":null}]},\"as\":\"seed\"},{\"assert_rows\":{\"unique_by\":[\"a\"]}}]",
  )
  assert_true(
    evaluate_rows(
      row_kernel(nullable, 1),
      row_capture(nullable),
      1,
      { remaining: 10000, max_frames: 100, },
      row_output(),
    )
    is Err(AssertionNullKey(0, 0)),
  )
}

///|
test "json pick traverses admitted objects and composes nullable parents" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"inner\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"leaf\":{\"type\":\"number\",\"nullable\":false}}}}}},\"rows\":[{\"id\":1,\"payload\":{\"inner\":{\"leaf\":3}}},{\"id\":2,\"payload\":null}]},\"as\":\"seed\"},{\"json_pick\":{\"column\":\"payload\",\"path\":[\"inner\",\"leaf\"],\"output\":\"picked\"}}]",
  )
  let result = evaluate_rows(
    row_kernel(owner, 1),
    row_capture(owner),
    2,
    { remaining: 10000, max_frames: 100, },
    row_output(),
  ).unwrap()
  assert_eq(result.names, ["id", "payload", "picked"])
  assert_true(result.rows[0][2] is Number(3.0))
  assert_true(result.rows[1][2] is Null)
}

///|
test "capture conversion admits both layouts before copying and spends shared work" {
  let owner = row_owner("")
  let input = capture_values(owner, 0, max_rows=2, {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 100,
  }).unwrap()
  // Captured row references/cells: 6; copied row references/cells/names: 8.
  let workspace = { limit: 14, live: 0, peak: 0, }
  let control = { remaining: 10, max_frames: 0, }
  let table = table_from_capture_bounded(input, control, workspace).unwrap()
  assert_eq(control.remaining, 0)
  assert_eq(workspace.live, 14)
  assert_eq(workspace.peak, 14)
  assert_eq(table.names, ["a", "b"])
  assert_true(table.rows[0][0] is Number(1.0))
  assert_true(
    table_from_capture_bounded(input, { remaining: 10, max_frames: 0, }, {
      limit: 13,
      live: 0,
      peak: 0,
    })
    is Err(RowLimit),
  )
  assert_true(
    table_from_capture_bounded(input, { remaining: 9, max_frames: 0, }, {
      limit: 14,
      live: 0,
      peak: 0,
    })
    is Err(RowLimit),
  )
  assert_true(
    table_from_capture_bounded(input, control, { limit: 14, live: 0, peak: 0, })
    is Err(RowLimit),
  )
  assert_true(
    table_from_capture_bounded(
      input,
      { remaining: 10, max_frames: 0, },
      workspace,
    )
    is Err(InvalidRowLimits),
  )
  // Output layout mutation cannot alter admitted capture row containers.
  table.rows[0][0] = Number(99.0)
  assert_true(capture(captured_cell(input, 0, 0).unwrap()) is Number(1.0))
  assert_true(
    table_from_capture_bounded(input, { remaining: 10, max_frames: 0, }, {
      limit: 14,
      live: 0,
      peak: 0,
    }).unwrap().rows[0][0]
    is Number(1.0),
  )
}

///|
test "conversion work is not reset before row execution" {
  let owner = row_owner(",{\"select\":[\"b\",\"a\"]}")
  let input = capture_values(owner, 0, max_rows=2, {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 100,
  }).unwrap()
  // Conversion consumes 10; select metadata and rows consume 18 more.
  let exact = { remaining: 28, max_frames: 0, }
  let table = table_from_capture_bounded(input, exact, {
    limit: 14,
    live: 0,
    peak: 0,
  }).unwrap()
  assert_eq(
    evaluate_rows_with_workspace(
      row_kernel(owner, 1),
      table,
      2,
      exact,
      row_output(),
      { limit: 22, live: 0, peak: 0, },
    ).unwrap().rows.length(),
    2,
  )
  assert_eq(exact.remaining, 0)
  let short = { remaining: 27, max_frames: 0, }
  let table2 = table_from_capture_bounded(input, short, {
    limit: 14,
    live: 0,
    peak: 0,
  }).unwrap()
  assert_true(
    evaluate_rows_with_workspace(
      row_kernel(owner, 1),
      table2,
      2,
      short,
      row_output(),
      { limit: 22, live: 0, peak: 0, },
    )
    is Err(RowLimit),
  )
}

///|
test "row workspace exact projection limit and failure isolation" {
  let owner = row_owner(",{\"select\":[\"b\",\"a\"]}")
  let kernel = row_kernel(owner, 1)
  let input = row_capture(owner)
  // Input: 2 names + 2 row references + 4 cells. Kernel view: 2.
  // Ordinals: 2. Projection metadata: 4. Output: 4 cells + 2 rows.
  let exact = { limit: 22, live: 0, peak: 0, }
  let result = evaluate_rows_with_workspace(
    kernel,
    input,
    2,
    { remaining: 1000, max_frames: 10, },
    row_output(),
    exact,
  ).unwrap()
  assert_eq(result.names, ["b", "a"])
  assert_eq(result.rows.length(), 2)
  assert_eq(exact.live, 22)
  assert_eq(exact.peak, 22)
  let short = { limit: 21, live: 0, peak: 0, }
  assert_true(
    evaluate_rows_with_workspace(
      kernel,
      input,
      2,
      { remaining: 1000, max_frames: 10, },
      row_output(),
      short,
    )
    is Err(RowLimit),
  )
  assert_true(short.live <= short.limit)
  // A failed operation cannot reuse a partly consumed workspace. A fresh
  // invocation remains independent, and the borrowed input is unchanged.
  assert_true(
    evaluate_rows_with_workspace(
      kernel,
      input,
      2,
      { remaining: 1000, max_frames: 10, },
      row_output(),
      short,
    )
    is Err(InvalidRowLimits),
  )
  assert_eq(input.names, ["a", "b"])
  assert_true(input.rows[0][0] is Number(1.0))
  assert_eq(
    evaluate_rows_with_workspace(
      kernel,
      input,
      2,
      { remaining: 1000, max_frames: 10, },
      row_output(),
      { limit: 22, live: 0, peak: 0, },
    ).unwrap().rows.length(),
    2,
  )
}

///|
test "row workspace releases discarded filter snapshots and bounds retained rows" {
  let owner = row_owner(",{\"filter\":\"a > 10\"}")
  // Eight input entries + two ordinals + two output names = twelve.
  // One two-entry snapshot and one binary continuation; no output survives.
  let workspace = { limit: 15, live: 0, peak: 0, }
  let result = evaluate_rows_with_workspace(
    row_kernel(owner, 1),
    row_capture(owner),
    2,
    { remaining: 1000, max_frames: 10, },
    row_output(),
    workspace,
  ).unwrap()
  assert_eq(result.rows.length(), 0)
  assert_eq(workspace.live, 12)
  assert_eq(workspace.peak, 15)
  assert_true(
    evaluate_rows_with_workspace(
      row_kernel(owner, 1),
      row_capture(owner),
      2,
      { remaining: 1000, max_frames: 10, },
      row_output(),
      { limit: 14, live: 0, peak: 0, },
    )
    is Err(Evaluation(0, 0, { kind: WorkspaceLimit, .. })),
  )
  let map_owner = row_owner(",{\"derive\":{}}")
  // Empty map still preserves both rows. Retained output entries accumulate,
  // but each input snapshot is released before constructing the next one.
  let map_workspace = { limit: 20, live: 0, peak: 0, }
  assert_eq(
    evaluate_rows_with_workspace(
      row_kernel(map_owner, 1),
      row_capture(map_owner),
      2,
      { remaining: 1000, max_frames: 10, },
      row_output(),
      map_workspace,
    ).unwrap().rows.length(),
    2,
  )
  assert_eq(map_workspace.live, 18)
  assert_eq(map_workspace.peak, 20)
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
