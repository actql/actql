///|
test "checked retained projection rename and copies reuse exact per-value quantities" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let material = source.representation.unwrap()
  let input = retained_scan_fixture(owner, source)
  let seed = prepare_retained_producer_scan(
    input,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  let original = prepare_streamed_fixed_producer_measurement(
    [input],
    Step(0),
    max_rows=2,
    max_value_bytes=100,
    { max_work: 1000, max_bytes: 1000, max_nodes: 1000, max_depth: 10, },
  ).unwrap()
  attach_retained_producer_measurement(original, seed).unwrap()
  for row in 0..<2 {
    append_retained_producer_scan_values(seed, output_fixture_row(owner, row)).unwrap()
    |> ignore
  }
  finish_retained_producer_scan(seed).unwrap() |> ignore
  let saved = material.value_measurement
  for
    (fields, steps, expected) in [
      ("[\"n\"]", "[{\"select\":[\"n\"]}]", (4, 2, 2)),
      ("[{\"renamed\":\"s\"}]", "[{\"select\":[\"renamed\"]}]", (4, 10, 2)),
      (
        "[{\"a\":\"n\"},{\"b\":\"n\"}]",
        "[{\"select\":[\"a\",\"b\"]}]",
        (6, 4, 4),
      ),
      ("[\"s\",\"n\"]", "[{\"select\":[\"s\",\"n\"]}]", (6, 12, 4)),
    ] {
    let receiver = projected_consumer(owner, fields, steps, target=Step(1))
    let input = prepare_producer_read(
      receiver,
      bind_completed_input(receiver, 0, owner, source).unwrap(),
      1000,
      10000,
    ).unwrap()
    for reused in [false, true] {
      material.value_measurement = if reused { saved } else { None }
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
        { max_work: 1000, max_bytes: 1000, max_nodes: 1000, max_depth: 10, },
      ).unwrap()
      attach_retained_producer_measurement(measurement, scan).unwrap()
      assert_true(
        reuse_retained_scan_identity(
          scan,
          prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap(),
        ),
      )
      assert_eq(reuse_retained_scan_values(scan), reused)
      if !reused {
        for row in 0..<2 {
          append_retained_producer_scan_values(
            scan,
            output_fixture_row(owner, row),
          ).unwrap()
          |> ignore
        }
      }
      let verified = finish_retained_producer_scan(scan).unwrap()
      assert_true(verified_producer_scan_matches(verified, input))
      assert_true(physical_equal(verified.receipt, material.receipt))
      assert_eq(
        (
          1000 - measurement.budget.work,
          1000 - measurement.budget.bytes,
          1000 - measurement.budget.nodes,
        ),
        expected,
      )
    }
    // A projection-specific shortage must preserve the ordinary first failure
    // and partially consumed budget. No maximum/aggregate substitutes for it.
    for shortage in 0..<4 {
      let mut baseline = None
      for optimized in [false, true] {
        material.value_measurement = if optimized { saved } else { None }
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
          max_value_bytes=if shortage == 3 { 0 } else { 100 },
          {
            max_work: if shortage == 0 {
              expected.0 - 1
            } else {
              1000
            },
            max_bytes: if shortage == 1 {
              expected.1 - 1
            } else {
              1000
            },
            max_nodes: if shortage == 2 {
              expected.2 - 1
            } else {
              1000
            },
            max_depth: 10,
          },
        ).unwrap()
        attach_retained_producer_measurement(measurement, scan).unwrap()
        assert_true(
          reuse_retained_scan_identity(
            scan,
            prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap(),
          ),
        )
        assert_false(reuse_retained_scan_values(scan))
        assert_eq(scan.stream.rows, 0)
        for row in 0..<2 {
          append_retained_producer_scan_values(
            scan,
            output_fixture_row(owner, row),
          ).unwrap()
          |> ignore
        }
        let diagnostic = match finish_retained_producer_scan(scan) {
          Err(InputGuard(MeasurementWork)) => (1, -1, -1)
          Err(InputGuard(Measurement(_, row, column, _))) => (2, row, column)
          Err(InputGuard(ValueBytes(_, row, column))) => (3, row, column)
          _ => (0, -1, -1)
        }
        assert_true(diagnostic.0 > 0)
        let observed = (
          diagnostic,
          measurement.budget.work,
          measurement.budget.bytes,
          measurement.budget.nodes,
        )
        if baseline is Some(prior) {
          assert_eq(observed, prior)
        } else {
          baseline = Some(observed)
        }
      }
    }
  }
  // A narrow successful measurement does not attest omitted source columns.
  material.value_measurement = saved
  let narrow = material.value_measurement.unwrap()
  material.value_measurement = Some({
    ..narrow,
    columns: [narrow.columns[0]],
    column_usage: [narrow.column_usage[0]],
    work: 4,
    bytes: 2,
    nodes: 2,
  })
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
    { max_work: 1000, max_bytes: 1000, max_nodes: 1000, max_depth: 10, },
  ).unwrap()
  attach_retained_producer_measurement(measurement, scan).unwrap()
  assert_true(
    reuse_retained_scan_identity(
      scan,
      prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap(),
    ),
  )
  assert_false(reuse_retained_scan_values(scan))
  assert_eq(scan.stream.rows, 0)
  assert_eq(measurement.budget.bytes, 1000)
}
