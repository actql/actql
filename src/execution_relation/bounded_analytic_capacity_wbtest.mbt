///|
fn analytic_borrow_capacity_fixture(
  expression? : String = "{\"literal\":\"x\"}",
  recursive? : Bool = false,
) -> GeneratedSequence raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}" +
    (if recursive {
      ",\"nested\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}"
    } else {
      ""
    }) +
    "},\"rows\":[{\"id\":1,\"label\":\"a\"" +
    (if recursive { ",\"nested\":[1]" } else { "" }) +
    "}]},\"as\":\"seed\"},{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":{\"preceding\":1},\"end\":\"current_row\"},\"functions\":{\"names\":{\"fn\":\"string_agg\",\"expr\":" +
    expression +
    ",\"delimiter\":\"|\",\"max_bytes\":65536}}}}]",
  )
  let sequence = prepared_sequence(owner)
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [sequence_fragment_context(sequence, 1, 1L)],
    ["analytic_1"],
    100000,
    10000,
  ).unwrap()
  select_generated_sequence_step(generated, 1).unwrap()
}

///|
test "bounded analytic quote preserves staged frame Text before output admission" {
  let generated = analytic_borrow_capacity_fixture()
  guard generated_sequence_step_at(generated, 0) is Some(@lower.RowStep(kernel)) else {
    fail("original analytic kernel missing")
  }
  assert_true(bounded_analytic_borrows_input(kernel))
  let base = string_group_constructor_limits()
  let limits = { ..base, rows: { ..base.rows, max_rows: 100, }, }
  assert_eq(
    bounded_analytic_staged_text_capacity(kernel, limits),
    Some(52454400L),
  )
  let tiny = {
    ..limits,
    rows: {
      ..limits.rows,
      output_values: { ..limits.rows.output_values, max_text_bytes: 1, },
    },
  }
  assert_eq(
    bounded_analytic_staged_text_capacity(kernel, tiny),
    bounded_analytic_staged_text_capacity(kernel, limits),
  )
  let measure : FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_nodes: 100,
    max_bytes: 5000,
    max_depth: 10,
  }
  let bounded = generated_bounded_sequence_capacity(generated, tiny, measure).unwrap()
  assert_true(bounded.execution_bytes >= 52454400L)
  assert_true(
    bounded.execution_bytes >
    generated_bounded_sequence_capacity(
      generated,
      { ..tiny, rows: { ..tiny.rows, max_rows: 99, }, },
      measure,
    ).unwrap().execution_bytes,
  )
}

///|
test "analytic immutable result branches are inspected without exported CASE views" {
  let expression = lowered(
    (
      #|{"case":{"when":[{"when":{"gt":[{"literal":2},{"literal":1}]},"then":{"literal":"a"}}],"else":{"literal":"b"}}}
    ),
  )
  assert_true(@lower.expression_view_entries(expression) > 0)
  assert_true(@lower.expression_result_borrows_payload(expression))
  assert_false(
    @lower.expression_result_borrows_payload(
      lowered(
        (
          #|{"upper":{"literal":"a"}}
        ),
      ),
    ),
  )
  for
    generated in [
      analytic_borrow_capacity_fixture(recursive=true),
      analytic_borrow_capacity_fixture(
        expression="{\"upper\":{\"field\":\"label\"}}",
      ),
    ] {
    guard generated_sequence_step_at(generated, 0)
      is Some(@lower.RowStep(kernel)) else {
      fail("original fallback analytic missing")
    }
    assert_false(bounded_analytic_borrows_input(kernel))
    let limits = string_group_constructor_limits()
    let measure : FixedInputGuardMeasureLimits = {
      max_work: 100000,
      max_nodes: 100,
      max_bytes: 5000,
      max_depth: 10,
    }
    let bounded = generated_bounded_sequence_capacity(
      generated, limits, measure,
    ).unwrap()
    let full = generated_sequence_capacity(generated, limits, measure).unwrap()
    assert_eq(bounded.retained_bytes, full.retained_bytes)
    assert_eq(bounded.execution_bytes, full.execution_bytes)
  }
}

///|
test "actual analytic frames retain all Text results and preserve exact workspace refusal cleanup" {
  let schema =
    #|{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}}
  let rows =
    #|[{"id":1,"label":null},{"id":2,"label":{"literal":"a"}},{"id":3,"label":{"literal":"b"}},{"id":4,"label":{"literal":"a"}}]
  let operation =
    #|"analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"frame":{"start":{"preceding":1},"end":"current_row"},"functions":{"names":{"fn":"string_agg","expr":{"literal":"x"},"delimiter":"|","max_bytes":3}}}
  let (_, started, source) = bounded_relation_start(
    schema,
    rows,
    operation,
    "analytic_0",
    true,
    max_work=100000,
    max_entries=10000,
  )
  let active = started.unwrap()
  guard drive_bounded_group(active) is BoundedGroupComplete(output, ..) else {
    fail("original analytic frame constructor did not complete")
  }
  assert_eq(completed_row_count(output), 4)
  for row in 0..<4 {
    assert_true(
      completed_cell(output, row, 2) is Some(Text(text)) &&
      text == (if row == 0 { "x" } else { "x|x" }),
    )
  }
  let peak = active.state.workspace.peak
  assert_true(peak > 1)
  assert_true(cleanup_bounded_group_execution(active).unwrap())
  assert_eq(active.state.workspace.live, 0)
  assert_true(completed_output_available(source))
  for (slots, succeeds) in [(peak, true), (peak - 1, false)] {
    let (_, started, source) = bounded_relation_start(
      schema,
      rows,
      operation,
      "analytic_0",
      true,
      max_work=100000,
      max_entries=slots,
    )
    let active = started.unwrap()
    let terminal = drive_bounded_group(active)
    if succeeds {
      assert_true(terminal is BoundedGroupComplete(_, ..))
    } else {
      assert_true(terminal is BoundedGroupFailed(Rows(RowLimit), ..))
    }
    assert_true(cleanup_bounded_group_execution(active).unwrap())
    assert_eq(active.state.workspace.live, 0)
    assert_true(completed_output_available(source))
  }
}
