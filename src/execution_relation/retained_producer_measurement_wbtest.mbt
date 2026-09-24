///|
test "retained input measurement shares exact cell-backed budget through output" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  let physical : FixedInputGuardMeasureLimits = {
    max_work: 1000,
    max_bytes: 1000,
    max_nodes: 1000,
    max_depth: 10,
  }
  let measurement = prepare_streamed_fixed_producer_measurement(
    [input],
    Step(0),
    max_rows=2,
    max_value_bytes=100,
    physical,
  ).unwrap()
  let output = prepare_admitted_output_stream(
    producer_read_receiver(input),
    Step(0),
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  assert_true(
    attach_fixed_producer_stream_measurement(measurement, output)
    is Err(ForeignInput),
  )
  let scan = prepare_retained_producer_scan(
    input,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  attach_retained_producer_measurement(measurement, scan).unwrap()
  assert_true(
    attach_retained_producer_measurement(measurement, scan) is Err(ForeignInput),
  )
  for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
    append_retained_producer_scan_wire(scan, row, retained_row_test_limits()).unwrap()
    |> ignore
  }
  finish_retained_producer_scan(scan).unwrap() |> ignore
  assert_eq(measurement.next_input, 1)
  assert_eq(physical.max_bytes - measurement.budget.bytes, 12)
  attach_fixed_producer_stream_measurement(measurement, output).unwrap()
  for row in 0..<2 {
    let values = output_fixture_row(owner, row)
    append_admitted_output_stream(output, 1, column => values.get(column)).unwrap()
    |> ignore
  }
  let (receipt, _) = finish_admitted_output_stream(output).unwrap()
  let measured = finish_fixed_producer_stream_measurement(measurement, receipt).unwrap()
  assert_eq(fixed_producer_stream_measurement_usage(measured), (10, 14, 6))
}

///|
test "encoded output charging keeps ordered guard failure after input usage" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  let measurement = prepare_streamed_fixed_producer_measurement(
    [input],
    Step(0),
    max_rows=2,
    max_value_bytes=100,
    { max_work: 1000, max_bytes: 13, max_nodes: 1000, max_depth: 10, },
  ).unwrap()
  let scan = prepare_retained_producer_scan(
    input,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  attach_retained_producer_measurement(measurement, scan).unwrap()
  for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
    append_retained_producer_scan_wire(scan, row, retained_row_test_limits()).unwrap()
    |> ignore
  }
  finish_retained_producer_scan(scan).unwrap() |> ignore
  let output = prepare_admitted_output_stream(
    producer_read_receiver(input),
    Step(0),
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  attach_fixed_producer_stream_measurement(measurement, output).unwrap()
  for row in 0..<2 {
    let values = output_fixture_row(owner, row)
    append_admitted_output_stream(output, 1, column => values.get(column)).unwrap()
    |> ignore
  }
  let (receipt, _) = finish_admitted_output_stream(output).unwrap()
  assert_true(
    finish_fixed_producer_stream_measurement(measurement, receipt)
    is Err(Measurement(Output, 1, 0, @encode.OutputLimit)),
  )
  assert_eq(measurement.initial.max_bytes - measurement.budget.bytes, 13)
}

///|
test "retained input measurement failure cannot be replaced by unmeasured scan" {
  let owner = capture_fixture()
  for mode in 0..<3 {
    let (source, _) = retained_fixture(owner, Ref(true))
    let input = retained_scan_fixture(owner, source)
    let measurement = prepare_streamed_fixed_producer_measurement(
      [input],
      Step(0),
      max_rows=2,
      max_value_bytes=if mode == 0 { 0 } else { 100 },
      {
        max_work: 100,
        max_bytes: if mode == 1 {
          1
        } else {
          1000
        },
        max_nodes: 100,
        max_depth: 10,
      },
    ).unwrap()
    let scan = prepare_retained_producer_scan(
      input,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    attach_retained_producer_measurement(measurement, scan).unwrap()
    for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
      append_retained_producer_scan_wire(scan, row, retained_row_test_limits()).unwrap()
      |> ignore
    }
    if mode == 2 {
      cancel_retained_producer_scan(scan) |> ignore
    }
    assert_true(finish_retained_producer_scan(scan) is Err(_))
    assert_false(measurement.open)
    let replacement = prepare_retained_producer_scan(
      input,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    assert_true(
      attach_retained_producer_measurement(measurement, replacement)
      is Err(ForeignInput),
    )
  }
}
