///|
fn indexed_guard_signature(
  result : Result[ManagedOutputValueReceipt, ManagedOutputValueIssue],
) -> (Int, Int, Int) {
  match result {
    Ok(_) => (0, -1, -1)
    Err(Guard(MeasurementWork)) => (1, -1, -1)
    Err(Guard(ValueBytes(Output, row, column))) => (2, row, column)
    Err(Guard(Measurement(Output, row, column, cause))) =>
      if cause is @encode.OutputLimit {
        (3, row, column)
      } else {
        (-1, -1, -1)
      }
    _ => (-1, -1, -1)
  }
}

///|
test "indexed rejection preserves ordinary measurement precedence position and consumed ledger" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), index_cells=4)
  let receiver = typed_receiver(
    owner, "[{\"select\":[\"n\",\"s\"]},{\"select\":[\"n\",\"s\"]}]",
  )
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0), row_kernel(receiver, 1)],
    1000,
    10000,
    100,
  ).unwrap()
  let cells = [output_fixture_row(receiver, 0), output_fixture_row(receiver, 1)]
  let mut comparisons = 0
  for work in [0, 1, 2, 3, 4, 5, 6, 1000] {
    for bytes in [0, 1, 4, 5, 6, 11, 12, 1000] {
      for nodes in [0, 1, 2, 3, 4, 1000] {
        for ceiling in [0, 1, 3, 4, 5, 6, 1000] {
          let limits : FixedInputGuardMeasureLimits = {
            max_work: work,
            max_bytes: bytes,
            max_nodes: nodes,
            max_depth: 10,
          }
          let ordinary = prepare_managed_output_values(
            receiver,
            Step(1),
            2,
            stream_value_limits(),
            ceiling,
            limits,
          ).unwrap()
          for row in cells {
            append_managed_output_values(ordinary, 2, column => row.get(column)).unwrap()
          }
          let expected = indexed_guard_signature(
            finish_managed_output_values(ordinary),
          )
          assert_true(expected.0 >= 0)
          let selected = prepare_managed_view_selection(plan, [0, 1], 4, 1000).unwrap()
          let reused = prepare_managed_output_values(
            receiver,
            Step(1),
            2,
            stream_value_limits(),
            ceiling,
            limits,
          ).unwrap()
          let port = prepare_managed_selected_view_output_port(
            selected,
            reused,
            (_ : Unit) => true,
          ).unwrap()
          let result = match finish_managed_view_output(port, ()) {
            Ok(receipt) => Ok(receipt)
            Err(Values(issue)) => Err(issue)
            _ => Err(Closed)
          }
          assert_eq(indexed_guard_signature(result), expected)
          assert_eq(
            (
              reused.measurement.work,
              reused.measurement.bytes,
              reused.measurement.nodes,
            ),
            (
              ordinary.measurement.work,
              ordinary.measurement.bytes,
              ordinary.measurement.nodes,
            ),
          )
          assert_true(finish_managed_view_output(port, ()) is Err(Closed))
          comparisons += 1
        }
      }
    }
  }
  assert_eq(comparisons, 2688)
}

///|
test "indexed summary cannot resolve an unproven depth obligation" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), index_cells=4)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\",\"s\"]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  let selected = prepare_managed_view_selection(plan, [0, 1], 4, 1000).unwrap()
  let reused = prepare_managed_output_values(
    receiver,
    Step(0),
    2,
    stream_value_limits(),
    0,
    { ..managed_test_measure_limits(), max_depth: 0, },
  ).unwrap()
  let port = prepare_managed_selected_view_output_port(selected, reused, (
    _ : Unit,
  ) => true).unwrap()
  assert_true(
    finish_managed_view_output(port, ()) is Err(OutputRepresentationRequired),
  )
  assert_eq(reused.measurement.work, reused.initial.max_work)
}

///|
test "indexed diagnostic resolution does not precede execution proof or live binding" {
  for verified in [false, true] {
    let owner = capture_fixture()
    let live = Ref(true)
    let source = managed_read_fixture(owner, live, index_cells=4)
    let receiver = typed_receiver(owner, "[{\"select\":[\"n\",\"s\"]}]")
    let input = prepare_managed_producer_read(
      receiver, 0, owner, source, 1000, 10000,
    ).unwrap()
    let plan = prepare_managed_view_plan(
      input,
      [row_kernel(receiver, 0)],
      1000,
      10000,
      100,
    ).unwrap()
    let selected = prepare_managed_view_selection(plan, [0, 1], 4, 1000).unwrap()
    let stream = prepare_managed_output_values(
      receiver,
      Step(0),
      2,
      stream_value_limits(),
      0,
      managed_test_measure_limits(),
    ).unwrap()
    let port = prepare_managed_selected_view_output_port(selected, stream, (
      _ : Unit,
    ) => {
      if verified {
        live.val = false
      }
      verified
    }).unwrap()
    let result = finish_managed_view_output(port, ())
    if verified {
      assert_true(result is Err(ForeignBinding))
    } else {
      assert_true(result is Err(Unverified))
    }
    assert_eq(stream.measurement.work, stream.initial.max_work)
    assert_false(stream.open)
  }
}

///|
test "indexed failure position is the first offending occurrence not the maximum" {
  let index = managed_row_measurements_from_cells([
    (120, 1, false),
    (160, 1, false),
  ]).unwrap()
  let budget : FixedInputGuardBudget = {
    work: 100,
    bytes: 1000,
    nodes: 100,
    depth: 10,
  }
  assert_true(
    measure_managed_output_index(index, 2, 1, 100, budget)
    is Err(ValueBytes(Output, 0, 0)),
  )
  assert_eq((budget.work, budget.bytes, budget.nodes), (98, 880, 99))
}

///|
test "contradictory private index cannot turn an aggregate violation into success" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true), index_cells=4)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\",\"s\"]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  let selected = prepare_managed_view_selection(plan, [0, 1], 4, 1000).unwrap()
  // Whitebox fault injection, unavailable through the public opaque handle.
  for i in 0..<4 {
    assert_true(managed_row_measurement_set(selected.index, i, (1, 1, false)))
  }
  let stream = prepare_managed_output_values(
    receiver,
    Step(0),
    2,
    stream_value_limits(),
    100,
    { ..managed_test_measure_limits(), max_bytes: 6, },
  ).unwrap()
  let port = prepare_managed_selected_view_output_port(selected, stream, (
    _ : Unit,
  ) => true).unwrap()
  assert_true(finish_managed_view_output(port, ()) is Err(InconsistentFacts))
  assert_false(stream.open)
}
