///|
test "retained measurement evidence skips repeat measurement but not consumer charges" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  for pass in 0..<3 {
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
    // Cached quantities do not grant representation authority on their own.
    assert_true(reusable_retained_value_measurement(scan, measurement) is None)
    assert_true(
      reuse_retained_scan_identity(
        scan,
        prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap(),
      ),
    )
    if pass > 0 {
      // Even the same material is insufficient for a different ordered view.
      let first = scan.wire_columns[0]
      scan.wire_columns[0] = scan.wire_columns[1]
      assert_true(
        reusable_retained_value_measurement(scan, measurement) is None,
      )
      scan.wire_columns[0] = first
      assert_true(
        reusable_retained_value_measurement(scan, measurement) is Some(_),
      )
    }
    for row in 0..<2 {
      append_retained_producer_scan_values(scan, output_fixture_row(owner, row)).unwrap()
      |> ignore
    }
    if pass == 0 {
      assert_true(scan.measurement_reuse is None)
      assert_true(source.representation.unwrap().value_measurement is None)
      assert_eq(measurement.budget.bytes, 988)
    } else {
      assert_true(scan.measurement_reuse is Some(_))
      // No per-row canonical measurement occurred. Charging is committed only
      // when the complete scan's identity and live representation are verified.
      assert_eq(measurement.budget.bytes, 1000)
    }
    finish_retained_producer_scan(scan).unwrap() |> ignore
    assert_eq(
      (
        measurement.budget.work,
        measurement.budget.bytes,
        measurement.budget.nodes,
      ),
      (994, 988, 996),
    )
    assert_true(fixed_producer_inputs_measured(measurement))
    let independent = retain_admitted_output_stream(
      source.representation.unwrap().receipt,
      (),
      () => true,
    )
    assert_true(retained_output_material(independent).value_measurement is None)
  }
}

///|
test "retained measurement insufficient summaries keep ordinary failure frontiers" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  // Establish one complete successful summary, then compare every stricter
  // budget/ceiling to the unoptimized path with the same exact representation.
  for seed in [true, false] {
    for limit in 0..<6 {
      if seed && limit != 0 {
        continue
      }
      let mut expected = None
      for optimized in [false, true] {
        if seed && !optimized {
          continue
        }
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
          max_value_bytes=if !seed && limit == 0 { 1 } else { 100 },
          {
            max_work: if !seed && limit == 1 {
              2
            } else {
              1000
            },
            max_bytes: if !seed && limit == 2 {
              1
            } else {
              1000
            },
            max_nodes: if !seed && limit == 3 {
              1
            } else {
              1000
            },
            max_depth: if !seed && limit == 4 {
              0
            } else {
              10
            },
          },
        ).unwrap()
        attach_retained_producer_measurement(measurement, scan).unwrap()
        if optimized {
          assert_true(
            reuse_retained_scan_identity(
              scan,
              prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap(),
            ),
          )
        }
        for row in 0..<2 {
          append_retained_producer_scan_values(
            scan,
            output_fixture_row(owner, row),
          ).unwrap()
          |> ignore
        }
        if !seed && limit < 4 {
          assert_true(scan.measurement_reuse is None)
        }
        let result = finish_retained_producer_scan(scan)
        let diagnostic = match result {
          Ok(_) => (0, -1, -1)
          Err(InputGuard(MeasurementWork)) => (1, -1, -1)
          Err(InputGuard(Measurement(_, row, column, _))) => (2, row, column)
          Err(InputGuard(ValueBytes(_, row, column))) => (3, row, column)
          _ => (4, -1, -1)
        }
        let observed = (
          diagnostic,
          measurement.budget.work,
          measurement.budget.bytes,
          measurement.budget.nodes,
        )
        if expected is Some(prior) {
          assert_eq(observed, prior)
        } else {
          expected = Some(observed)
        }
      }
    }
  }
}

///|
test "retained measurement partial scan cannot publish or revive evidence" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  let material = source.representation.unwrap()
  for revoke in [false, true] {
    let live = Ref(true)
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
        prepare_trusted_retained_scan_reuse(input, live, (live, _) => live.val).unwrap(),
      ),
    )
    append_retained_producer_scan_values(scan, output_fixture_row(owner, 0)).unwrap()
    |> ignore
    if revoke {
      append_retained_producer_scan_values(scan, output_fixture_row(owner, 1)).unwrap()
      |> ignore
      live.val = false
    }
    assert_true(finish_retained_producer_scan(scan) is Err(_))
    assert_true(material.value_measurement is None)
    assert_false(fixed_producer_inputs_measured(measurement))
  }
}

///|
test "retained measurement paired diagnostic" {
  guard @env.get_env_var("ACTQL_RETAINED_MEASUREMENT_DIAGNOSTIC") == Some("1") else {
    return
  }
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  let material = source.representation.unwrap()
  let evidence = prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap()
  let rows = [output_fixture_row(owner, 0), output_fixture_row(owner, 1)]
  for pair in 0..<8 {
    for leg in 0..<2 {
      let reuse = (pair + leg) % 2 == 0
      let clock = @bench.monotonic_clock_start()
      for _ in 0..<10000 {
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
        assert_true(reuse_retained_scan_identity(scan, evidence))
        if !reuse {
          material.value_measurement = None
        }
        for row in rows {
          append_retained_producer_scan_values(scan, row).unwrap() |> ignore
        }
        finish_retained_producer_scan(scan).unwrap() |> ignore
        assert_eq(
          (
            measurement.budget.work,
            measurement.budget.bytes,
            measurement.budget.nodes,
          ),
          (994, 988, 996),
        )
      }
      let elapsed = @bench.monotonic_clock_end(clock)
      if pair > 0 {
        println(
          "RETAINED_MEASUREMENT pair=" +
          pair.to_string() +
          " reuse=" +
          reuse.to_string() +
          " elapsed=" +
          elapsed.to_string(),
        )
      }
    }
  }
}
