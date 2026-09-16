///|
test "owned representation evidence skips encoding but retains consumer accounting" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  assert_true(
    prepare_trusted_retained_scan_reuse(input, (), (_, _) => false) is None,
  )
  let evidence = prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap()
  for insufficient in [false, true] {
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
        max_bytes: if insufficient {
          1
        } else {
          1000
        },
        max_nodes: 1000,
        max_depth: 10,
      },
    ).unwrap()
    attach_retained_producer_measurement(measurement, scan).unwrap()
    assert_true(reuse_retained_scan_identity(scan, evidence))
    assert_false(reuse_retained_scan_identity(scan, evidence))
    for row in 0..<2 {
      append_retained_producer_scan_values(scan, output_fixture_row(owner, row)).unwrap()
      |> ignore
    }
    // Hash writer still contains only the opening array: no rows were encoded.
    @encode.end_array(scan.stream.writer)
    let (_, bytes, _, _) = @encode.finish_hash_metrics(scan.stream.writer)
    assert_eq(bytes, 2)
    let finished = finish_retained_producer_scan(scan)
    if insufficient {
      assert_true(finished is Err(InputGuard(_)))
      assert_false(fixed_producer_inputs_measured(measurement))
    } else {
      let verified = finished.unwrap()
      assert_true(verified_producer_scan_matches(verified, input))
      assert_true(
        physical_equal(verified.receipt, source.representation.unwrap().receipt),
      )
      assert_true(fixed_producer_inputs_measured(measurement))
      assert_eq(1000 - measurement.budget.bytes, 12)
    }
    assert_true(scan.reuse is None)
    assert_true(scan.stream.buffer.rows.is_empty())
  }
}

///|
test "reuse rejects foreign bindings revocation truncation and untrusted wire rows" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  for mode in 0..<5 {
    let generation_live = Ref(true)
    let evidence = prepare_trusted_retained_scan_reuse(input, generation_live, (
      live,
      _,
    ) => live.val).unwrap()
    let scan = prepare_retained_producer_scan(
      input,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    let other = retained_scan_fixture(owner, source)
    let foreign = prepare_trusted_retained_scan_reuse(other, (), (_, _) => true).unwrap()
    assert_false(reuse_retained_scan_identity(scan, foreign))
    assert_true(reuse_retained_scan_identity(scan, evidence))
    if mode == 0 {
      generation_live.val = false
      assert_true(
        append_retained_producer_scan_values(scan, output_fixture_row(owner, 0))
        is Err(Unavailable),
      )
    } else if mode == 1 {
      assert_true(
        append_retained_producer_scan_wire(
          scan,
          "{}",
          retained_row_test_limits(),
        )
        is Err(IdentityMismatch),
      )
    } else if mode == 2 {
      assert_true(
        append_retained_producer_scan_values(
          scan,
          output_fixture_row(capture_fixture(), 0),
        )
        is Err(_),
      )
    } else {
      append_retained_producer_scan_values(scan, output_fixture_row(owner, 0)).unwrap()
      |> ignore
      if mode == 3 {
        append_retained_producer_scan_values(scan, output_fixture_row(owner, 1)).unwrap()
        |> ignore
        generation_live.val = false
      }
    }
    assert_true(finish_retained_producer_scan(scan) is Err(_))
    assert_true(scan.reuse is None)
  }
}

///|
test "identity reuse cannot waive encoding capacity" {
  let owner = capture_fixture()
  let (source, _) = retained_fixture(owner, Ref(true))
  let input = retained_scan_fixture(owner, source)
  let evidence = prepare_trusted_retained_scan_reuse(input, (), (_, _) => true).unwrap()
  let scan = prepare_retained_producer_scan(
    input,
    2,
    stream_value_limits(),
    { ..row_wire_limits(), max_bytes: 2, },
    64,
  ).unwrap()
  assert_false(reuse_retained_scan_identity(scan, evidence))
  assert_true(
    append_retained_producer_scan_values(scan, output_fixture_row(owner, 0))
    is Err(_),
  )
}
