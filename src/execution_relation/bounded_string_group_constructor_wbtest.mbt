///|
fn string_group_constructor_limits() -> SequenceExecutionLimits {
  let values : ValueLimits = {
    max_nodes: 100,
    max_text_bytes: 5000,
    max_depth: 10,
    max_work: 100000,
  }
  {
    rows: {
      max_rows: 10,
      retained_entries: 100,
      metadata_entries: 100,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }
}

///|
test "ordered DISTINCT and scalar filtered StringAgg borrow only their original input forest" {
  let limits = string_group_constructor_limits()
  let measure : FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_nodes: 100,
    max_bytes: 5000,
    max_depth: 10,
  }
  for
    (aggregate, fragment) in [
      (
        (
          #|{"fn":"string_agg","field":"payload","order_by":[{"payload":"asc"}],"distinct":true,"delimiter":"|","max_bytes":4096}
        ),
        false,
      ),
      (
        (
          #|{"fn":"string_agg","field":"payload","filter":"id <= 2","order_by":[{"id":"asc"}],"delimiter":"|","max_bytes":4096}
        ),
        true,
      ),
    ] {
    let generated = string_group_capacity_fixture(aggregate~, fragment~)
    guard generated_sequence_step_at(generated, 0)
      is Some(@lower.RowStep(kernel)) else {
      fail("original StringAgg constructor kernel missing")
    }
    assert_true(bounded_string_group_borrows_input(kernel))
    assert_true(bounded_group_step_supported(generated, kernel))
    let quote = generated_bounded_sequence_capacity(generated, limits, measure).unwrap()
    let full = generated_sequence_capacity(generated, limits, measure).unwrap()
    assert_true(quote.retained_bytes <= full.retained_bytes)
    assert_true(quote.execution_bytes < full.execution_bytes)
    let larger = generated_bounded_sequence_capacity(
      generated,
      {
        ..limits,
        rows: {
          ..limits.rows,
          input_values: {
            ..limits.rows.input_values,
            max_nodes: 1000000,
            max_text_bytes: 10000000,
          },
        },
      },
      { ..measure, max_nodes: 1000000, max_bytes: 10000000, },
    ).unwrap()
    assert_eq(larger.retained_bytes, quote.retained_bytes)
    assert_eq(larger.execution_bytes, quote.execution_bytes)
    let slots = generated_bounded_sequence_capacity(
      generated,
      { ..limits, rows: { ..limits.rows, operation_entries: 10001, }, },
      measure,
    ).unwrap()
    assert_eq(slots.execution_bytes - quote.execution_bytes, 256L)
  }
}

///|
test "scalar filtered StringAgg cannot prepare without its original Fragment context" {
  let generated = string_group_capacity_fixture(
    aggregate=(
      #|{"fn":"string_agg","field":"payload","filter":"id <= 2","order_by":[{"id":"asc"}],"delimiter":"|","max_bytes":4096}
    ),
    fragment=true,
  )
  guard generated_sequence_step_at(generated, 0) is Some(@lower.RowStep(kernel)) else {
    fail("original filtered StringAgg constructor missing")
  }
  assert_true(bounded_string_group_borrows_input(kernel))
  assert_true(bounded_group_step_supported(generated, kernel))
  assert_true(
    prepare_generated_sequence(
      registered_relation_contracts(),
      generated.sequence,
      [],
      generated.retained_ids,
      100000,
      10000,
    )
    is Err(_),
  )
}

///|
test "actual ordered DISTINCT and scalar filter preserve duplicates NULL exact workspace and cleanup" {
  let schema =
    #|{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":true}}
  let rows =
    #|[{"id":4,"label":{"literal":"b"}},{"id":3,"label":null},{"id":2,"label":{"literal":"a"}},{"id":1,"label":{"literal":"b"}}]
  for
    (aggregate, fragment, expected) in [
      (
        (
          #|{"fn":"string_agg","field":"label","order_by":[{"label":"asc"}],"distinct":true,"delimiter":"|","max_bytes":3}
        ),
        false,
        "a|b",
      ),
      (
        (
          #|{"fn":"string_agg","field":"label","filter":"id <= 2","order_by":[{"id":"asc"}],"delimiter":"|","max_bytes":3}
        ),
        true,
        "b|a",
      ),
    ] {
    let operation = "\"group\":{\"by\":[],\"aggregates\":{\"text\":" +
      aggregate +
      "}}"
    let (_, started, source) = bounded_relation_start(
      schema,
      rows,
      operation,
      "group_0",
      fragment,
      max_work=100000,
      max_entries=10000,
    )
    let execution = started.unwrap()
    guard drive_bounded_group(execution) is BoundedGroupComplete(output, ..) else {
      fail("original StringAgg did not complete")
    }
    guard completed_cell(output, 0, 0) is Some(Text(actual)) else {
      fail("original StringAgg output text missing")
    }
    assert_eq(actual, expected)
    let peak = execution.state.workspace.peak
    assert_true(peak > 1)
    assert_true(cleanup_bounded_group_execution(execution).unwrap())
    assert_eq(execution.state.workspace.live, 0)
    assert_true(completed_output_available(source))
    let (_, exact, exact_source) = bounded_relation_start(
      schema,
      rows,
      operation,
      "group_0",
      fragment,
      max_work=100000,
      max_entries=peak,
    )
    let exact = exact.unwrap()
    assert_true(drive_bounded_group(exact) is BoundedGroupComplete(_, ..))
    assert_true(cleanup_bounded_group_execution(exact).unwrap())
    assert_eq(exact.state.workspace.live, 0)
    assert_true(completed_output_available(exact_source))
    let (_, short, short_source) = bounded_relation_start(
      schema,
      rows,
      operation,
      "group_0",
      fragment,
      max_work=100000,
      max_entries=peak - 1,
    )
    let short = short.unwrap()
    assert_true(
      drive_bounded_group(short) is BoundedGroupFailed(Rows(RowLimit), ..),
    )
    assert_true(cleanup_bounded_group_execution(short).unwrap())
    assert_eq(short.state.workspace.live, 0)
    assert_true(completed_output_available(short_source))
  }
}
