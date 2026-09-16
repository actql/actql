///|
fn retained_scan_fixture(
  owner : @lower.BoundPrepared,
  source : CompletedOutput,
) -> ProducerRead {
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
}

///|
test "typed retained input verifies full ordered source without JSON reconstruction" {
  let owner = capture_fixture()
  for mode in 0..<5 {
    let live = Ref(true)
    let (source, _) = retained_fixture(owner, live)
    let input = retained_scan_fixture(owner, source)
    let scan = prepare_retained_producer_scan(
      input,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    let measurement = prepare_streamed_fixed_producer_measurement(
      [input],
      Step(0),
      max_rows=2,
      max_value_bytes=100,
      {
        max_work: 1000,
        max_bytes: if mode == 4 {
          1
        } else {
          1000
        },
        max_nodes: 1000,
        max_depth: 10,
      },
    ).unwrap()
    attach_retained_producer_measurement(measurement, scan).unwrap()
    if mode == 2 {
      let foreign = output_fixture_row(capture_fixture(), 0)
      assert_true(append_retained_producer_scan_values(scan, foreign) is Err(_))
    } else {
      let first = output_fixture_row(owner, if mode == 1 { 1 } else { 0 })
      let projected = append_retained_producer_scan_values(scan, first).unwrap()
      assert_eq(projected.length(), 2)
      assert_false(fixed_producer_inputs_measured(measurement))
      if mode == 3 {
        live.val = false
        assert_true(
          append_retained_producer_scan_values(
            scan,
            output_fixture_row(owner, 1),
          )
          is Err(Unavailable),
        )
      } else {
        append_retained_producer_scan_values(
          scan,
          output_fixture_row(owner, if mode == 1 { 0 } else { 1 }),
        ).unwrap()
        |> ignore
      }
    }
    let result = finish_retained_producer_scan(scan)
    if mode == 0 {
      assert_true(verified_producer_scan_matches(result.unwrap(), input))
      assert_true(fixed_producer_inputs_measured(measurement))
      assert_eq(1000 - measurement.budget.bytes, 12)
    } else {
      assert_true(result is Err(_))
      assert_false(fixed_producer_inputs_measured(measurement))
    }
    assert_true(scan.stream.buffer.rows.is_empty())
  }
}

///|
test "retained producer scan validates whole identity without retaining rows" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let read = retained_scan_fixture(owner, source)
  let scan = prepare_retained_producer_scan(
    read,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  assert_false(scan.stream.retain_text)
  for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
    let values = append_retained_producer_scan_wire(
      scan,
      row,
      retained_row_test_limits(),
    ).unwrap()
    assert_eq(values.length(), read.columns.length())
    assert_true(scan.stream.buffer.rows.is_empty())
  }
  let verified = finish_retained_producer_scan(scan).unwrap()
  assert_eq(verified.receipt.rows, 2)
  assert_true(verified_producer_scan_matches(verified, read))
  let another_binding = retained_scan_fixture(owner, source)
  assert_false(verified_producer_scan_matches(verified, another_binding))
  assert_false(completed_has_cell_access(source))
  assert_true(finish_retained_producer_scan(scan) is Err(Closed))
}

///|
test "retained producer scan rejects wrong ordered content and truncated scan" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  for
    rows in [
      ["{\"n\":2,\"s\":\"😀\"}", "{\"n\":1,\"s\":\"é\"}"],
      ["{\"n\":1,\"s\":\"é\"}"],
      ["{\"n\":1,\"s\":\"x\"}", "{\"n\":2,\"s\":\"😀\"}"],
    ] {
    let scan = prepare_retained_producer_scan(
      retained_scan_fixture(owner, source),
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    for row in rows {
      append_retained_producer_scan_wire(scan, row, retained_row_test_limits()).unwrap()
      |> ignore
    }
    assert_true(finish_retained_producer_scan(scan) is Err(IdentityMismatch))
    assert_true(finish_retained_producer_scan(scan) is Err(Closed))
  }
}

///|
test "retained producer scan cancellation and source loss cannot authorize import" {
  let owner = capture_fixture()
  for cancelled in [true, false] {
    let live = Ref(true)
    let (source, _) = retained_fixture(owner, live)
    let scan = prepare_retained_producer_scan(
      retained_scan_fixture(owner, source),
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    append_retained_producer_scan_wire(
      scan,
      "{\"n\":1,\"s\":\"é\"}",
      retained_row_test_limits(),
    ).unwrap()
    |> ignore
    if cancelled {
      cancel_retained_producer_scan(scan) |> ignore
    } else {
      live.val = false
    }
    assert_true(finish_retained_producer_scan(scan) is Err(_))
    assert_true(scan.stream.buffer.rows.is_empty())
  }
}
