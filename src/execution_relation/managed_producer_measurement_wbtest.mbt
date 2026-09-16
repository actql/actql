///|
test "managed projection measurement reuses exact subtotals and maxima with per consumer charges" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true))
  for
    (fields, steps, expected) in [
      ("[\"n\"]", "[{\"select\":[\"n\"]}]", (4, 2, 2)),
      ("[{\"renamed\":\"s\"}]", "[{\"select\":[\"renamed\"]}]", (4, 10, 2)),
      (
        "[{\"a\":\"n\"},{\"b\":\"n\"}]",
        "[{\"select\":[\"a\",\"b\"]}]",
        (6, 4, 4),
      ),
      (
        "[{\"a\":\"s\"},{\"b\":\"n\"}]",
        "[{\"select\":[\"a\",\"b\"]}]",
        (6, 12, 4),
      ),
    ] {
    let receiver = projected_consumer(owner, fields, steps, target=Step(1))
    let input = prepare_managed_producer_read(
      receiver, 0, owner, source, 1000, 10000,
    ).unwrap()
    for _ in 0..<2 {
      // Original admission used a ceiling of 100. Exact observed maxima permit
      // this tighter requirement without a second value pass.
      let session = prepare_reused_managed_producer_measurement(
        [input],
        Step(0),
        max_rows=2,
        max_value_bytes=if expected.1 <= 4 { 1 } else { 6 },
        managed_test_measure_limits(),
        100,
      ).unwrap()
      assert_eq(
        (
          1000 - session.budget.work,
          1000 - session.budget.bytes,
          1000 - session.budget.nodes,
        ),
        expected,
      )
      assert_true(managed_producer_measurement_matches_inputs(session, [input]))
      let other = prepare_managed_producer_read(
        receiver, 0, owner, source, 1000, 10000,
      ).unwrap()
      assert_false(
        managed_producer_measurement_matches_inputs(session, [other]),
      )
      let output = prepare_reused_managed_output_values(
        session,
        stream_value_limits(),
      ).unwrap()
      assert_true(
        prepare_reused_managed_output_values(session, stream_value_limits())
        is Err(Guard(ForeignInput)),
      )
      let receipt = finish_managed_output_values(output).unwrap()
      assert_eq(managed_output_value_measurement(receipt), (0, 0, 0))
      assert_eq(
        managed_output_value_managed_measurement_usage(receipt),
        Some(expected),
      )
      assert_true(
        managed_output_value_managed_measurement_matches(receipt, session),
      )
      assert_true(managed_output_value_fixed_measurement_usage(receipt) is None)
    }
  }
}

///|
test "managed reused input and new output share one ledger and reject stale input" {
  let owner = capture_fixture()
  let live = Ref(true)
  let source = managed_read_fixture(owner, live)
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  for mode in 0..<5 {
    live.val = true
    let session = prepare_reused_managed_producer_measurement(
      [input],
      Step(0),
      max_rows=2,
      max_value_bytes=6,
      {
        ..managed_test_measure_limits(),
        max_bytes: if mode == 1 || mode == 4 {
          13
        } else {
          14
        },
      },
      100,
    ).unwrap()
    let output = prepare_reused_managed_output_values(
      session,
      stream_value_limits(),
    ).unwrap()
    for row in 0..<2 {
      let cells = output_fixture_row(owner, row)
      append_managed_output_values(output, 1, column => cells.get(column)).unwrap()
    }
    if mode == 2 || mode == 4 {
      live.val = false
    }
    if mode == 3 {
      cancel_managed_output_values(output) |> ignore
    }
    let result = finish_managed_output_values(output)
    match mode {
      0 => {
        let receipt = result.unwrap()
        assert_eq(
          managed_output_value_managed_measurement_usage(receipt),
          Some((10, 14, 6)),
        )
        assert_true(
          managed_output_value_managed_measurement_matches(receipt, session),
        )
        live.val = false
        assert_false(
          managed_output_value_managed_measurement_matches(receipt, session),
        )
      }
      1 => assert_true(result is Err(Guard(Measurement(Output, 1, 0, _))))
      2 | 4 => assert_true(result is Err(Guard(ForeignInput)))
      _ => assert_true(result is Err(Closed))
    }
  }
}

///|
test "managed summary shortages request ordered measurement rather than inventing first failure" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true))
  let receiver = typed_receiver(owner, "[{\"select\":[\"n\"]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  for
    limits in [
      { ..managed_test_measure_limits(), max_work: 5, },
      { ..managed_test_measure_limits(), max_bytes: 11, },
      { ..managed_test_measure_limits(), max_nodes: 3, },
      { ..managed_test_measure_limits(), max_depth: 1, },
    ] {
    assert_true(
      prepare_reused_managed_producer_measurement(
        [input],
        Step(0),
        max_rows=2,
        max_value_bytes=6,
        limits,
        100,
      )
      is Err(InputRepresentationRequired(0)),
    )
  }
  assert_true(
    prepare_reused_managed_producer_measurement(
      [input],
      Step(0),
      max_rows=2,
      max_value_bytes=5,
      managed_test_measure_limits(),
      100,
    )
    is Err(InputRepresentationRequired(0)),
  )
  assert_true(
    prepare_reused_managed_producer_measurement(
      [input],
      Step(0),
      max_rows=1,
      max_value_bytes=6,
      managed_test_measure_limits(),
      100,
    )
    is Err(InputRows),
  )
  assert_true(
    prepare_reused_managed_producer_measurement(
      [input],
      Step(0),
      max_rows=2,
      max_value_bytes=6,
      managed_test_measure_limits(),
      0,
    )
    is Err(InputRepresentationRequired(0)),
  )
  assert_true(
    prepare_reused_managed_producer_measurement(
      [input],
      Step(0),
      max_rows=2,
      max_value_bytes=6,
      { ..managed_test_measure_limits(), max_bytes: -1, },
      100,
    )
    is Err(InvalidLimits),
  )
}
