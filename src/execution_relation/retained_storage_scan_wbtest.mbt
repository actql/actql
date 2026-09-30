///|
test "full retained storage scan is bounded and exact without constructing a consumer" {
  let owner = capture_fixture()
  let (output, _) = retained_fixture(owner, Ref(true))
  let storage = prepare_producer_storage(output, 1000, 10000).unwrap()
  let scan = prepare_retained_storage_scan(
    storage,
    2,
    stream_value_limits(),
    row_wire_limits(),
    64,
  ).unwrap()
  for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
    let values = append_retained_storage_scan_wire(
      scan,
      row,
      retained_row_test_limits(),
    ).unwrap()
    assert_eq(values.length(), 2)
    assert_true(scan.stream.buffer.rows.is_empty())
  }
  let verified = finish_retained_storage_scan(scan).unwrap()
  assert_true(verified_storage_scan_relation_identity(verified) is None)
  assert_true(verified_storage_scan_matches(verified, storage))
  assert_false(
    verified_storage_scan_matches(
      verified,
      prepare_producer_storage(output, 1000, 10000).unwrap(),
    ),
  )
  assert_false(completed_has_cell_access(output))
  assert_true(finish_retained_storage_scan(scan) is Err(Closed))
}

///|
test "retained identity scan hashes the exact Relation envelope without keeping rows" {
  let live = Ref(true)
  let (output, _) = retained_fixture(capture_fixture(), live)
  let storage = prepare_producer_storage(output, 1000, 10000).unwrap()
  let scan = prepare_retained_relation_identity_scan(
    storage,
    2,
    stream_value_limits(),
    row_wire_limits(),
    { ..row_wire_limits(), max_bytes: 65, },
    0,
  ).unwrap()
  for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
    append_retained_storage_scan_wire(scan, row, retained_row_test_limits()).unwrap()
    |> ignore
    assert_true(scan.stream.buffer.rows.is_empty())
  }
  let verified = finish_retained_storage_scan(scan).unwrap()
  let identity = verified_storage_scan_relation_identity(verified).unwrap()
  // Independent SHA-256 of the literal UTF-8 Relation envelope, not the rows CID.
  assert_eq(
    logical_relation_cid(identity),
    "sha256:5f089a447a51c56f479c2c6258d8c3b687ec1368bf8e0bc28eda2d53efa0e5b8",
  )
  assert_eq(logical_relation_usage(identity).0, 65)
  assert_eq(logical_relation_usage(identity).2, 2)
  assert_eq(output_stream_value_usage(verified.receipt), {
    nodes: 6,
    text_bytes: 10,
    work: 16,
  })
  assert_true(verified_storage_scan_matches(verified, storage))
  live.val = false
  assert_true(verified_storage_scan_relation_identity(verified) is None)
}

///|
test "retained Relation identity cannot bypass content checks or envelope limits" {
  let owner = capture_fixture()
  let (output, _) = retained_fixture(owner, Ref(true))
  let storage = prepare_producer_storage(output, 1000, 10000).unwrap()
  for mode in 0..<5 {
    let scan = prepare_retained_relation_identity_scan(
      storage,
      2,
      stream_value_limits(),
      row_wire_limits(),
      { ..row_wire_limits(), max_bytes: if mode == 4 { 64 } else { 65 }, },
      0,
    ).unwrap()
    if mode == 2 {
      assert_true(cancel_retained_storage_scan(scan))
      assert_true(finish_retained_storage_scan(scan) is Err(Closed))
    } else if mode == 3 {
      assert_true(
        append_retained_storage_scan_values(
          scan,
          output_fixture_row(capture_fixture(), 0),
        )
        is Err(Encoding(Admission(ForeignCheckedValue(0, _)))),
      )
      assert_true(finish_retained_storage_scan(scan) is Err(Closed))
    } else {
      for row in 0..<(if mode == 1 { 1 } else { 2 }) {
        append_retained_storage_scan_values(
          scan,
          output_fixture_row(owner, if mode == 0 { 1 - row } else { row }),
        ).unwrap()
        |> ignore
      }
      let result = finish_retained_storage_scan(scan)
      if mode == 4 {
        assert_true(
          result is Err(Encoding(Wire(Encoding(@encode.OutputLimit)))),
        )
      } else {
        assert_true(result is Err(IdentityMismatch))
      }
      assert_true(finish_retained_storage_scan(scan) is Err(Closed))
    }
  }
  assert_true(producer_storage_available(storage))
}

///|
test "verified canonical Store copy stays bound to the live retained receipt" {
  let live = Ref(true)
  let (output, _) = retained_fixture(capture_fixture(), live)
  let storage = prepare_producer_storage(output, 1000, 10000).unwrap()
  let receipt = storage.output.representation.unwrap().receipt
  let (cid, bytes, _, rows) = output_stream_identity(receipt)
  assert_true(
    retained_storage_canonical_copy_matches(storage, cid, bytes, rows),
  )
  assert_false(
    retained_storage_canonical_copy_matches(storage, cid, bytes - 1, rows),
  )
  assert_false(
    retained_storage_canonical_copy_matches(storage, cid, bytes, rows - 1),
  )
  assert_false(
    retained_storage_canonical_copy_matches(
      storage, "sha256:wrong", bytes, rows,
    ),
  )
  live.val = false
  assert_false(
    retained_storage_canonical_copy_matches(storage, cid, bytes, rows),
  )
}

///|
test "typed storage transfer preserves exact provenance and rejects reordered values" {
  let owner = capture_fixture()
  for mode in 0..<3 {
    let (output, _) = retained_fixture(owner, Ref(true))
    let storage = prepare_producer_storage(output, 1000, 10000).unwrap()
    let scan = prepare_retained_storage_scan(
      storage,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    if mode == 2 {
      assert_true(
        append_retained_storage_scan_values(
          scan,
          output_fixture_row(capture_fixture(), 0),
        )
        is Err(_),
      )
    } else {
      for row in 0..<2 {
        let values = output_fixture_row(
          owner,
          if mode == 1 {
            1 - row
          } else {
            row
          },
        )
        assert_eq(
          append_retained_storage_scan_values(scan, values).unwrap().length(),
          2,
        )
        assert_true(scan.stream.buffer.rows.is_empty())
      }
    }
    let result = finish_retained_storage_scan(scan)
    if mode == 0 {
      assert_true(verified_storage_scan_matches(result.unwrap(), storage))
    } else {
      assert_true(result is Err(_))
    }
  }
}

///|
test "storage transfer cannot verify reordered truncated or changed content" {
  let (output, _) = retained_fixture(capture_fixture(), Ref(true))
  let storage = prepare_producer_storage(output, 1000, 10000).unwrap()
  for
    rows in [
      ["{\"n\":2,\"s\":\"😀\"}", "{\"n\":1,\"s\":\"é\"}"],
      ["{\"n\":1,\"s\":\"é\"}"],
      ["{\"n\":1,\"s\":\"x\"}", "{\"n\":2,\"s\":\"😀\"}"],
    ] {
    let scan = prepare_retained_storage_scan(
      storage,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    for row in rows {
      append_retained_storage_scan_wire(scan, row, retained_row_test_limits()).unwrap()
      |> ignore
    }
    assert_true(finish_retained_storage_scan(scan) is Err(IdentityMismatch))
    assert_true(finish_retained_storage_scan(scan) is Err(Closed))
  }
}

///|
test "storage transfer respects row ceiling cancellation and lost holding" {
  for cancelled in [true, false] {
    let live = Ref(true)
    let (output, _) = retained_fixture(capture_fixture(), live)
    let storage = prepare_producer_storage(output, 1000, 10000).unwrap()
    assert_true(
      prepare_retained_storage_scan(
        storage,
        1,
        stream_value_limits(),
        row_wire_limits(),
        64,
      )
      is Err(Admission(CaptureLimit)),
    )
    let scan = prepare_retained_storage_scan(
      storage,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
    ).unwrap()
    if cancelled {
      cancel_retained_storage_scan(scan) |> ignore
    } else {
      live.val = false
    }
    assert_true(
      append_retained_storage_scan_wire(
        scan,
        "{\"n\":1,\"s\":\"é\"}",
        retained_row_test_limits(),
      )
      is Err(_),
    )
    assert_true(finish_retained_storage_scan(scan) is Err(_))
  }
}
