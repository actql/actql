///|
test "identity metadata is advanced on its original scan before the unchanged row traversal" {
  let source = export_fixture(capture_fixture())
  let wire = { ..row_wire_limits(), max_nodes: 10, }
  let scan = start_completed_relation_identity_scan(
    source,
    2,
    stream_value_limits(),
    wire,
    wire,
    publication_schema_limits(),
    10000,
    47,
    incremental_metadata=true,
  ).unwrap()
  assert_true(scan.stream is None)
  let preparation = scan.preparation.unwrap()
  assert_true(preparation.schema_cursor is None)
  assert_eq(preparation.column, 0)
  assert_eq(preparation.names.length(), 0)
  let mut metadata_steps = 0
  while scan.preparation is Some(_) {
    assert_eq(
      advance_completed_relation_identity_scan(scan, 1).unwrap(),
      (false, 1),
    )
    metadata_steps += 1
  }
  assert_true(metadata_steps > 1)
  assert_true(preparation.closed)
  let mut row_steps = 0
  while true {
    let (done, used) = advance_completed_relation_identity_scan(scan, 1).unwrap()
    row_steps += used
    if done {
      break
    }
  }
  assert_eq(row_steps, 29)
  assert_eq(
    completed_relation_identity_scan_work(scan),
    (metadata_steps + row_steps).to_int64(),
  )
  let receipt = finish_completed_relation_identity_scan(scan).unwrap()
  assert_eq(
    logical_relation_cid(completed_relation_export_identity(receipt)),
    "sha256:5f089a447a51c56f479c2c6258d8c3b687ec1368bf8e0bc28eda2d53efa0e5b8",
  )
  assert_true(completed_relation_export_matches_output(receipt, source))
}

///|
test "identity metadata stop and work refusal retain original completed source" {
  for stop in [false, true] {
    let available = Ref(true)
    let original = export_fixture(capture_fixture())
    let source = restrict_completed_output(original, () => available.val)
    let wire = { ..row_wire_limits(), max_nodes: 10, }
    let scan = start_completed_relation_identity_scan(
      source,
      2,
      stream_value_limits(),
      wire,
      wire,
      publication_schema_limits(),
      1,
      47,
      incremental_metadata=true,
    ).unwrap()
    let preparation = scan.preparation.unwrap()
    assert_eq(
      advance_completed_relation_identity_scan(scan, 1).unwrap(),
      (false, 1),
    )
    if stop {
      available.val = false
    }
    if stop {
      assert_true(
        advance_completed_relation_identity_scan(scan, 1) is Err(Unavailable),
      )
    } else {
      assert_true(
        advance_completed_relation_identity_scan(scan, 1)
        is Err(Admission(CaptureLimit)),
      )
    }
    assert_true(preparation.closed)
    assert_true(scan.preparation is None)
    assert_true(scan.stream is None)
    assert_eq(scan.workspace.live, 0)
    assert_eq(completed_relation_identity_scan_work(scan), 1L)
    assert_true(completed_output_available(original))
    assert_true(finish_completed_relation_identity_scan(scan) is Err(Closed))
  }
}
