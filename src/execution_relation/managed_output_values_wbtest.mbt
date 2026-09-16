///|
fn managed_test_measure_limits() -> FixedInputGuardMeasureLimits {
  { max_work: 1000, max_bytes: 1000, max_nodes: 1000, max_depth: 10, }
}

///|
test "managed values share fixed input budget and reject stale or consumed sessions" {
  let owner = capture_fixture()
  for mode in 0..<4 {
    let live = Ref(true)
    let (source, _) = retained_fixture(owner, live)
    let input = retained_scan_fixture(owner, source)
    let measurement = prepare_streamed_fixed_producer_measurement(
      [input],
      Step(0),
      max_rows=2,
      max_value_bytes=100,
      {
        max_work: 100,
        max_bytes: if mode == 1 {
          13
        } else {
          14
        },
        max_nodes: 100,
        max_depth: 10,
      },
    ).unwrap()
    assert_true(
      prepare_fixed_managed_output_values(measurement, stream_value_limits())
      is Err(Guard(ForeignInput)),
    )
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
    assert_eq(measurement.initial.max_bytes - measurement.budget.bytes, 12)
    let output = prepare_fixed_managed_output_values(
      measurement,
      stream_value_limits(),
    ).unwrap()
    assert_true(physical_equal(output.measurement, measurement.budget))
    assert_true(
      prepare_fixed_managed_output_values(measurement, stream_value_limits())
      is Err(Guard(ForeignInput)),
    )
    for row in 0..<2 {
      let cells = output_fixture_row(owner, row)
      append_managed_output_values(output, 1, column => cells.get(column)).unwrap()
    }
    if mode == 2 {
      live.val = false
    }
    if mode == 3 {
      cancel_managed_output_values(output) |> ignore
    }
    let result = finish_managed_output_values(output)
    match mode {
      0 => {
        let receipt = result.unwrap()
        assert_eq(managed_output_value_measurement(receipt), (4, 2, 2))
        assert_eq(
          managed_output_value_fixed_measurement_usage(receipt),
          Some((10, 14, 6)),
        )
        assert_true(
          managed_output_value_fixed_measurement_matches(receipt, measurement),
        )
        live.val = false
        assert_false(
          managed_output_value_fixed_measurement_matches(receipt, measurement),
        )
      }
      1 => assert_true(result is Err(Guard(Measurement(Output, 1, 0, _))))
      2 => assert_true(result is Err(Guard(ForeignInput)))
      _ => assert_true(result is Err(Closed))
    }
    assert_true(finish_managed_output_values(output) is Err(Closed))
  }
}

///|
test "managed values admit complete content with exact measurement but no logical CID" {
  let owner = capture_fixture()
  let stream = prepare_managed_output_values(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  for row in 0..<2 {
    let values = output_fixture_row(owner, row)
    append_managed_output_values(stream, values.length(), column => {
      values.get(column)
    }).unwrap()
    assert_true(stream.buffer.rows.is_empty())
  }
  let receipt = finish_managed_output_values(stream).unwrap()
  assert_eq(managed_output_value_row_count(receipt), 2)
  assert_eq(managed_output_value_usage(receipt), {
    nodes: 6,
    text_bytes: 10,
    work: 16,
  })
  assert_eq(managed_output_value_measurement(receipt), (6, 12, 4))
  assert_true(managed_output_value_receipt_matches(receipt, owner, Step(1)))
  assert_false(
    managed_output_value_receipt_matches(receipt, capture_fixture(), Step(1)),
  )
  assert_false(managed_output_value_receipt_matches(receipt, owner, Step(0)))
  assert_true(finish_managed_output_values(stream) is Err(Closed))
  assert_true(append_managed_output_values(stream, 0, _ => None) is Err(Closed))
  let empty = prepare_managed_output_values(
    owner,
    Step(1),
    0,
    stream_value_limits(),
    0,
    { max_work: 0, max_bytes: 0, max_nodes: 0, max_depth: 0, },
  ).unwrap()
  let receipt = finish_managed_output_values(empty).unwrap()
  assert_eq(managed_output_value_row_count(receipt), 0)
  assert_eq(managed_output_value_measurement(receipt), (0, 0, 0))
}

///|
test "managed values preserve cumulative limits and deferred measurement location" {
  let owner = capture_fixture()
  for kind in 0..<4 {
    let stream = prepare_managed_output_values(
      owner,
      Step(1),
      if kind == 0 {
        1
      } else {
        2
      },
      { ..stream_value_limits(), max_nodes: if kind == 1 { 5 } else { 10000 }, },
      if kind == 2 {
        4
      } else {
        100
      },
      {
        ..managed_test_measure_limits(),
        max_bytes: if kind == 3 {
          11
        } else {
          1000
        },
      },
    ).unwrap()
    let first = output_fixture_row(owner, 0)
    append_managed_output_values(stream, first.length(), column => {
      first.get(column)
    }).unwrap()
    let second = output_fixture_row(owner, 1)
    let appended = append_managed_output_values(stream, second.length(), column => {
      second.get(column)
    })
    if kind < 2 {
      assert_true(appended is Err(Admission(CaptureLimit)))
      assert_true(finish_managed_output_values(stream) is Err(Closed))
    } else {
      appended.unwrap()
      let finished = finish_managed_output_values(stream)
      if kind == 2 {
        assert_true(finished is Err(Guard(ValueBytes(Output, 1, 1))))
      } else {
        assert_true(finished is Err(Guard(Measurement(Output, 1, 1, _))))
      }
    }
    assert_true(stream.buffer.rows.is_empty())
  }
}

///|
test "managed values cannot hide foreign cells behind a prior guard failure" {
  let owner = capture_fixture()
  let stream = prepare_managed_output_values(
    owner,
    Step(1),
    2,
    stream_value_limits(),
    0,
    managed_test_measure_limits(),
  ).unwrap()
  let own = output_fixture_row(owner, 0)
  append_managed_output_values(stream, own.length(), column => own.get(column)).unwrap()
  assert_true(stream.issue is Some(ValueBytes(Output, 0, 0)))
  let foreign = output_fixture_row(capture_fixture(), 1)
  assert_true(
    append_managed_output_values(stream, foreign.length(), column => {
      foreign.get(column)
    })
    is Err(Admission(ForeignCheckedValue(1, 0))),
  )
  assert_true(finish_managed_output_values(stream) is Err(Closed))
}

///|
test "managed values reject reentrant finish and cancellation leaves no receipt" {
  let owner = capture_fixture()
  for cancel in [false, true] {
    let stream = prepare_managed_output_values(
      owner,
      Step(1),
      2,
      stream_value_limits(),
      100,
      managed_test_measure_limits(),
    ).unwrap()
    let own = output_fixture_row(owner, 0)
    let appended = append_managed_output_values(stream, own.length(), column => {
      assert_true(finish_managed_output_values(stream) is Err(Closed)) catch {
        _ => abort("reentrant finish")
      }
      if cancel {
        cancel_managed_output_values(stream) |> ignore
      }
      own.get(column)
    })
    if cancel {
      assert_true(appended is Err(_))
    } else {
      appended.unwrap()
    }
    cancel_managed_output_values(stream) |> ignore
    assert_false(cancel_managed_output_values(stream))
    assert_true(finish_managed_output_values(stream) is Err(Closed))
    assert_true(stream.buffer.rows.is_empty())
  }
}
