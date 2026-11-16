///|
fn scalar_distinct_capacity_fixture() -> (GeneratedSequence, ProducerRead) raise {
  let (source_owner, source) = bounded_append_source(
    "[{\"a\":1,\"b\":\"x\"},{\"a\":1,\"b\":\"x\"},{\"a\":2,\"b\":\"y\"},{\"a\":null,\"b\":\"n\"},{\"a\":1,\"b\":\"x\"},{\"a\":3,\"b\":\"z\"},{\"a\":null,\"b\":\"n\"}]",
    schema="{\"a\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"string\",\"nullable\":false}}",
  )
  let receiver = bounded_binding_rows_receiver(
    source_owner,
    metadata_operation=Some(
      "{\"distinct\":[\"a\",\"b\"],\"from\":\"rows\",\"as\":\"derived\"}",
    ),
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let input = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  (generated, input)
}

///|
test "whole scalar DISTINCT preserves full retained holding with bounded constructor scratch" {
  let (generated, _) = scalar_distinct_capacity_fixture()
  assert_true(generated.selected_steps is None)
  assert_true(generated.selected_prefix_end is None)
  assert_eq(@lower.sequence_count(generated.sequence), 1)
  guard generated_sequence_step_at(generated, 0) is Some(@lower.RowStep(kernel)) else {
    fail("actual DISTINCT kernel missing")
  }
  assert_true(bounded_distinct_borrows_input(kernel))
  let limits = compute_test_limits()
  let measure : FixedInputGuardMeasureLimits = {
    max_nodes: 10000,
    max_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let full = generated_sequence_capacity(generated, limits, measure).unwrap()
  let bounded = generated_bounded_sequence_capacity(generated, limits, measure).unwrap()
  assert_eq(bounded.retained_bytes, full.retained_bytes)
  assert_true(bounded.execution_bytes < full.execution_bytes)
  let selected = generated_bounded_sequence_capacity(
    select_generated_sequence_step(generated, 0).unwrap(),
    limits,
    measure,
  ).unwrap()
  assert_eq(
    bounded.execution_bytes,
    selected.execution_bytes + full.retained_bytes - selected.retained_bytes,
  )
  let unused = generated_bounded_sequence_capacity(
    generated,
    {
      ..limits,
      rows: {
        ..limits.rows,
        input_values: {
          ..limits.rows.input_values,
          max_nodes: 2830000,
          max_text_bytes: 20000000,
        },
      },
    },
    { ..measure, max_nodes: 2830000, max_bytes: 120034833, },
  ).unwrap()
  assert_eq(unused.retained_bytes, bounded.retained_bytes)
  assert_eq(unused.execution_bytes, bounded.execution_bytes)
  let workspace = generated_bounded_sequence_capacity(
    generated,
    {
      ..limits,
      rows: {
        ..limits.rows,
        operation_entries: limits.rows.operation_entries + 1,
      },
    },
    measure,
  ).unwrap()
  assert_eq(workspace.execution_bytes - bounded.execution_bytes, 256L)
  let output = generated_bounded_sequence_capacity(
    generated,
    {
      ..limits,
      rows: {
        ..limits.rows,
        output_values: {
          ..limits.rows.output_values,
          max_nodes: limits.rows.output_values.max_nodes + 1,
        },
      },
    },
    measure,
  ).unwrap()
  assert_eq(output.retained_bytes - bounded.retained_bytes, 256L)
  assert_eq(output.execution_bytes - bounded.execution_bytes, 256L)
}

///|
test "scalar DISTINCT constructor keeps original NULL Text order work and cleanup" {
  let (generated, input) = scalar_distinct_capacity_fixture()
  let control = @bounded.control()
  let execution = start_bounded_binding_rows(
    control,
    generated,
    input,
    100,
    run_limits().input_values,
    run_limits().output_values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  let output = presence_filter_complete(execution)
  assert_eq(completed_row_count(output), 4)
  let numbers : Array[Value] = [Number(1), Number(2), Null, Number(3)]
  let texts = ["x", "y", "n", "z"]
  for row in 0..<numbers.length() {
    match (completed_cell(output, row, 0), numbers[row]) {
      (Some(Number(actual)), Number(wanted)) => assert_eq(actual, wanted)
      (Some(Null), Null) => ()
      _ => fail("unexpected scalar DISTINCT survivor")
    }
    guard completed_cell(output, row, 1) is Some(Text(actual)) else {
      fail("DISTINCT lost original Text")
    }
    assert_eq(actual, texts[row])
  }
  assert_true(producer_read_available(input))
  let peak = execution.state.workspace.peak
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  let limited = start_bounded_binding_rows(
    @bounded.control(),
    generated,
    input,
    100,
    run_limits().input_values,
    run_limits().output_values,
    100000,
    100,
    peak - 1,
    10000,
  ).unwrap()
  let mut refused = false
  for _ in 0..<10000 {
    match advance_bounded_binding_rows(limited, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
        refused = true
        break
      }
      _ => fail("DISTINCT ignored its actual workspace frontier")
    }
  }
  assert_true(refused)
  assert_true(cleanup_bounded_binding_rows(limited).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "whole DISTINCT capacity keeps recursive presence and prefix fallback" {
  let (control, recursive, input) = nested_distinct_fixture()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(input.bound.receiver),
    [],
    ["distinct_0"],
    100000,
    10000,
  ).unwrap()
  let limits = compute_test_limits()
  let measure : FixedInputGuardMeasureLimits = {
    max_nodes: 10000,
    max_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let bounded = generated_bounded_sequence_capacity(generated, limits, measure).unwrap()
  let full = generated_sequence_capacity(generated, limits, measure).unwrap()
  assert_eq(bounded.retained_bytes, full.retained_bytes)
  assert_eq(bounded.execution_bytes, full.execution_bytes)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(recursive, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_true(cleanup_bounded_binding_rows(recursive).unwrap())
  let (control, presence, input) = presence_whole_distinct_fixture()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(input.bound.receiver),
    [],
    ["distinct_0"],
    100000,
    10000,
  ).unwrap()
  let bounded = generated_bounded_sequence_capacity(generated, limits, measure).unwrap()
  let full = generated_sequence_capacity(generated, limits, measure).unwrap()
  assert_eq(bounded.retained_bytes, full.retained_bytes)
  assert_eq(bounded.execution_bytes, full.execution_bytes)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(presence, 1).unwrap()
    is BoundedBindingRowsStopped(_, ..),
  )
  assert_true(cleanup_bounded_binding_rows(presence).unwrap())
  let (generated, _) = scalar_distinct_capacity_fixture()
  let owner = typed_receiver(
    generated_sequence_owner(generated),
    "[{\"distinct\":true},{\"select\":[\"a\",\"b\"]}]",
    target=Step(0),
  )
  let longer = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), 1).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let prefix = select_generated_sequence_prefix(longer, 0).unwrap()
  let bounded = generated_bounded_sequence_capacity(prefix, limits, measure).unwrap()
  let full = generated_sequence_capacity(prefix, limits, measure).unwrap()
  assert_eq(bounded.retained_bytes, full.retained_bytes)
  assert_eq(bounded.execution_bytes, full.execution_bytes)
  for invalid in [{ ..measure, max_nodes: -1, }, { ..measure, max_bytes: -1, }] {
    assert_true(
      generated_bounded_sequence_capacity(generated, limits, invalid) is None,
    )
  }
}

///|
test "whole scalar Set keeps full retention and real NULL Text survivor construction" {
  let schema = "{\"a\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"string\",\"nullable\":false}}"
  for operation in ["except", "intersect"] {
    let (_, started, inputs) = bounded_set_fixture(
      operation~,
      duplicates="distinct",
      left_schema=schema,
      right_schema=schema,
      left_rows="[{\"a\":1,\"b\":\"x\"},{\"a\":1,\"b\":\"x\"},{\"a\":2,\"b\":\"y\"},{\"a\":null,\"b\":\"n\"}]",
      right_rows="[{\"a\":1,\"b\":\"x\"},{\"a\":3,\"b\":\"z\"},{\"a\":null,\"b\":\"n\"}]",
      max_rows=7,
      max_work=100000,
      max_entries=10000,
    )
    let owner = inputs[0].bound.receiver
    let generated = prepare_generated_sequence(
      registered_relation_contracts(),
      prepared_sequence(owner),
      [],
      [operation + "_0"],
      100000,
      10000,
    ).unwrap()
    assert_true(generated.selected_steps is None)
    let limits = compute_test_limits()
    let measure : FixedInputGuardMeasureLimits = {
      max_nodes: 10000,
      max_bytes: 10000,
      max_depth: 100,
      max_work: 100000,
    }
    let full = generated_sequence_capacity(generated, limits, measure).unwrap()
    let bounded = generated_bounded_sequence_capacity(
      generated, limits, measure,
    ).unwrap()
    assert_eq(bounded.retained_bytes, full.retained_bytes)
    assert_true(bounded.execution_bytes < full.execution_bytes)
    let unused = generated_bounded_sequence_capacity(
      generated,
      {
        ..limits,
        rows: {
          ..limits.rows,
          input_values: {
            ..limits.rows.input_values,
            max_nodes: 2830000,
            max_text_bytes: 20000000,
          },
        },
      },
      { ..measure, max_nodes: 2830000, max_bytes: 120034833, },
    ).unwrap()
    assert_eq(unused.retained_bytes, bounded.retained_bytes)
    assert_eq(unused.execution_bytes, bounded.execution_bytes)
    let execution = started.unwrap()
    guard drive_bounded_set(execution) is BoundedSetComplete(output, ..) else {
      fail("original scalar Set did not complete")
    }
    assert_eq(
      completed_row_count(output),
      if operation == "except" {
        1
      } else {
        2
      },
    )
    if operation == "except" {
      assert_true(completed_cell(output, 0, 0) is Some(Number(2)))
      assert_true(completed_cell(output, 0, 1) is Some(Text("y")))
    } else {
      assert_true(completed_cell(output, 0, 0) is Some(Number(1)))
      assert_true(completed_cell(output, 0, 1) is Some(Text("x")))
      assert_true(completed_cell(output, 1, 0) is Some(Null))
      assert_true(completed_cell(output, 1, 1) is Some(Text("n")))
    }
    assert_true(inputs.all(producer_read_available))
    assert_true(cleanup_bounded_set(execution).unwrap())
  }
}
