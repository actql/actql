///|
fn identity_scan_fixture(
  source : CompletedOutput,
  work? : Int = 29,
  workspace? : Int = 47,
) -> CompletedRelationIdentityScan {
  // Two columns reserve 16 metadata slots and three ten-node writers.
  // The remaining slot holds one scalar/name measurement frame.
  let wire = { ..row_wire_limits(), max_nodes: 10, }
  start_completed_relation_identity_scan(
    source,
    2,
    stream_value_limits(),
    wire,
    wire,
    publication_schema_limits(),
    work,
    workspace,
  ).unwrap()
}

///|
test "incremental completed identity preserves the canonical receipt and exact limits" {
  let source = export_fixture(capture_fixture())
  let (reference, _) = export_relation_all(source)
  let scan = identity_scan_fixture(source)
  let mut done = false
  for _ in 0..<29 {
    let (finished, consumed) = advance_completed_relation_identity_scan(scan, 1).unwrap()
    assert_eq(consumed, 1)
    done = finished
  }
  assert_true(done)
  assert_eq(scan.work, 29)
  assert_eq(scan.workspace.peak, 47)
  let receipt = finish_completed_relation_identity_scan(scan).unwrap()
  assert_eq(scan.workspace.live, 0)
  assert_true(completed_relation_export_matches_output(receipt, source))
  assert_eq(
    output_stream_identity(completed_relation_export_content(receipt)).0,
    "sha256:1f3a78f3ede9a4385bbcbf098a3f0fdb9b16dc3e0e8d78f05255682d9c25f3e0",
  )
  assert_eq(
    logical_relation_cid(completed_relation_export_identity(receipt)),
    "sha256:5f089a447a51c56f479c2c6258d8c3b687ec1368bf8e0bc28eda2d53efa0e5b8",
  )
  let actual = completed_relation_export_measurement(receipt)
  let previous = completed_relation_export_measurement(reference)
  assert_eq(actual.row_count, previous.row_count)
  assert_eq(actual.admission_nodes, previous.admission_nodes)
  assert_eq(actual.admission_text_bytes, previous.admission_text_bytes)
  assert_eq(actual.admission_work, previous.admission_work)
  assert_eq(actual.column_rows, previous.column_rows)
  assert_eq(actual.column_bytes, previous.column_bytes)
  assert_eq(actual.column_nodes, previous.column_nodes)
  assert_eq(actual.column_max_value_bytes, previous.column_max_value_bytes)
  assert_eq(actual.column_null_rows, previous.column_null_rows)
  assert_eq(actual.column_admitted_depths, previous.column_admitted_depths)
  for (work, workspace) in [(28, 47), (29, 46)] {
    let scan = identity_scan_fixture(source, work~, workspace~)
    let mut rejected = false
    for _ in 0..<29 {
      match advance_completed_relation_identity_scan(scan, 1) {
        Err(Admission(CaptureLimit)) => {
          rejected = true
          break
        }
        Ok((_, _)) => ()
        _ => abort("unexpected identity failure")
      }
    }
    assert_true(rejected)
    assert_true(finish_completed_relation_identity_scan(scan) is Err(Closed))
    assert_eq(scan.workspace.live, 0)
    assert_true(completed_output_available(source))
  }
}

///|
test "identity scan cancellation releases nested traversal without revoking its input" {
  let items = Array::make(500, "0").join(",")
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"array\",\"nullable\":false," +
    "\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":[{\"payload\":[" +
    items +
    "]}]},\"as\":\"v\"},{\"select\":[\"payload\"],\"as\":\"selected\"}]",
  )
  let source = export_fixture(owner)
  let scan = start_completed_relation_identity_scan(
    source,
    1,
    stream_value_limits(),
    row_wire_limits(),
    row_wire_limits(),
    publication_schema_limits(),
    10000,
    100000,
  ).unwrap()
  for _ in 0..<100 {
    assert_eq(
      advance_completed_relation_identity_scan(scan, 1).unwrap(),
      (false, 1),
    )
  }
  assert_true(scan.phase is MeasureCell(_))
  assert_true(cancel_completed_relation_identity_scan(scan))
  assert_true(!cancel_completed_relation_identity_scan(scan))
  assert_eq(scan.workspace.live, 0)
  assert_true(completed_output_available(source))
  assert_true(advance_completed_relation_identity_scan(scan, 1) is Err(Closed))
  assert_true(finish_completed_relation_identity_scan(scan) is Err(Closed))
}

///|
test "completed identity yields inside both long column key streams" {
  let name = String::make(256, 'k')
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"" +
    name +
    "\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"" +
    name +
    "\":null}]},\"as\":\"v\"},{\"select\":[\"" +
    name +
    "\"],\"as\":\"selected\"}]",
  )
  let source = export_fixture(owner)
  // Three ten-node writer envelopes and one eight-slot column summary,
  // plus one measurement/key cursor. Four name chunks and six chunks per
  // wire key add to eight other transitions: 24 total advances.
  for
    (work, workspace, accepted) in [
      (24, 39, true),
      (23, 39, false),
      (24, 38, false),
    ] {
    let scan = identity_scan_fixture(source, work~, workspace~)
    let mut done = false
    let mut failed = false
    let mut payload_keys = 0
    let mut logical_keys = 0
    for _ in 0..<24 {
      let before = @encode.writer_progress(scan.stream.writer).0
      match advance_completed_relation_identity_scan(scan, 1) {
        Ok((finished, consumed)) => {
          assert_eq(consumed, 1)
          assert_true(
            @encode.writer_progress(scan.stream.writer).0 - before <= 68,
          )
          if scan.phase is EmitPayloadKey(_) {
            payload_keys += 1
          }
          if scan.phase is EmitLogicalKey(_) {
            logical_keys += 1
          }
          done = finished
          if done {
            break
          }
        }
        Err(Admission(CaptureLimit)) => {
          failed = true
          break
        }
        _ => abort("unexpected long-key identity failure")
      }
    }
    assert_eq(done, accepted)
    assert_eq(failed, !accepted)
    if accepted {
      assert_eq(scan.work, 24)
      assert_eq(scan.workspace.peak, 39)
      assert_eq(payload_keys, 6)
      assert_eq(logical_keys, 6)
      let receipt = finish_completed_relation_identity_scan(scan).unwrap()
      // Independent SHA-256 of [{"<256 k units>":null}] and the registered
      // {"sort":"relation","value":...} envelope, not execution output.
      assert_eq(
        output_stream_identity(completed_relation_export_content(receipt)).0,
        "sha256:d864ef15f2f6d814b1936a58cf852d84d66f6e3d70d14a1590dc5c26ccd8ea38",
      )
      assert_eq(
        logical_relation_cid(completed_relation_export_identity(receipt)),
        "sha256:62c52a4acd02f75317090121a9ff0dc7e2eeb11ac1176ef1e5e805bbb686476e",
      )
      assert_eq(completed_relation_export_measurement(receipt).column_bytes, [4])
    } else {
      assert_true(finish_completed_relation_identity_scan(scan) is Err(Closed))
    }
    assert_eq(scan.workspace.live, 0)
    assert_true(completed_output_available(source))
  }
  for logical in [false, true] {
    let scan = identity_scan_fixture(source, work=24, workspace=39)
    let mut reached = false
    for _ in 0..<24 {
      assert_false(advance_completed_relation_identity_scan(scan, 1).unwrap().0)
      if (logical && scan.phase is EmitLogicalKey(_)) ||
        (!logical && scan.phase is EmitPayloadKey(_)) {
        reached = true
        break
      }
    }
    assert_true(reached)
    let work = scan.work
    assert_true(cancel_completed_relation_identity_scan(scan))
    assert_eq(scan.work, work)
    assert_eq(scan.workspace.live, 0)
    assert_true(completed_output_available(source))
    assert_true(
      advance_completed_relation_identity_scan(scan, 1) is Err(Closed),
    )
    assert_true(finish_completed_relation_identity_scan(scan) is Err(Closed))
  }
}
