///|
test "exact resident values reuse avoids rows and preserves both consumer budgets" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  let evidence = prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap()
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
    assert_false(reuse_retained_scan_values(scan))
    assert_true(reuse_retained_scan_identity(scan, evidence))
    if pass == 0 {
      assert_false(reuse_retained_scan_values(scan))
      assert_eq(scan.stream.rows, 0)
      for row in 0..<2 {
        append_retained_producer_scan_values(
          scan,
          output_fixture_row(owner, row),
        ).unwrap()
        |> ignore
      }
    } else {
      assert_true(reuse_retained_scan_values(scan))
      assert_false(reuse_retained_scan_values(scan))
      assert_eq(scan.stream.rows, 2)
      assert_true(scan.stream.buffer.rows.is_empty())
      assert_eq(measurement.budget.bytes, 1000)
    }
    let usage = source.representation.unwrap().receipt.usage
    assert_eq(scan.stream.buffer.budget.nodes, usage.nodes)
    assert_eq(scan.stream.buffer.budget.text, usage.text_bytes)
    assert_eq(scan.stream.buffer.budget.work, usage.work)
    assert_true(
      verified_producer_scan_matches(
        finish_retained_producer_scan(scan).unwrap(),
        input,
      ),
    )
    assert_eq(
      (
        measurement.budget.work,
        measurement.budget.bytes,
        measurement.budget.nodes,
      ),
      (994, 988, 996),
    )
    assert_true(fixed_producer_inputs_measured(measurement))
  }
}

///|
test "values reuse insufficient admission budgets leave ordered fallback untouched" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  let evidence = prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap()
  let usage = source.representation.unwrap().receipt.usage
  for
    limits in [
      { ..stream_value_limits(), max_nodes: usage.nodes - 1, },
      { ..stream_value_limits(), max_text_bytes: usage.text_bytes - 1, },
      { ..stream_value_limits(), max_work: usage.work - 1, },
      { ..stream_value_limits(), max_depth: 0, },
    ] {
    let scan = prepare_retained_producer_scan(
      input,
      2,
      limits,
      row_wire_limits(),
      64,
    ).unwrap()
    assert_true(reuse_retained_scan_identity(scan, evidence))
    assert_false(reuse_retained_scan_values(scan))
    assert_eq(scan.stream.rows, 0)
    assert_eq(scan.stream.buffer.budget.nodes, 0)
    assert_eq(scan.stream.buffer.budget.text, 0)
    assert_eq(scan.stream.buffer.budget.work, 0)
    let mut failed = false
    for row in 0..<2 {
      if append_retained_producer_scan_values(
          scan,
          output_fixture_row(owner, row),
        )
        is Err(_) {
        failed = true
        break
      }
    }
    assert_true(failed)
    assert_true(finish_retained_producer_scan(scan) is Err(_))
  }
}

///|
test "values reuse still requires live generation at ordinary finish" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  for revoke_before in [true, false] {
    let live = Ref(true)
    let evidence = prepare_trusted_retained_scan_reuse(input, live, (live, _) => {
      live.val
    }).unwrap()
    let scan = prepare_retained_producer_scan(
      input,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    assert_true(reuse_retained_scan_identity(scan, evidence))
    if revoke_before {
      live.val = false
    }
    assert_eq(reuse_retained_scan_values(scan), !revoke_before)
    live.val = false
    assert_true(finish_retained_producer_scan(scan) is Err(Unavailable))
  }
}

///|
test "retained values reuse paired diagnostic" {
  guard @env.get_env_var("ACTQL_RETAINED_VALUES_DIAGNOSTIC") == Some("1") else {
    return
  }
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  let evidence = prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap()
  let rows = [output_fixture_row(owner, 0), output_fixture_row(owner, 1)]
  // Both legs keep the same successful measurement summary. This comparison
  // isolates whole-value traversal elimination from the earlier hash saving.
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
        if !reuse || !reuse_retained_scan_values(scan) {
          for row in rows {
            append_retained_producer_scan_values(scan, row).unwrap() |> ignore
          }
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
          "RETAINED_VALUES pair=" +
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
