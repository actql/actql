///|
fn snapshot_finish(
  preparation : CompletedRelationSnapshotPreparation,
  quantum : Int,
) -> Result[(String, Array[String]), CompletedExportIssue] raise {
  for _ in 0..<10000 {
    match preparation.advance(quantum) {
      Err(issue) => return Err(issue)
      Ok((done, used)) => {
        assert_true(used >= 0 && used <= quantum)
        if done {
          return preparation.finish()
        }
        assert_true(used > 0)
      }
    }
  }
  abort("snapshot preparation did not terminate")
}

///|
test "snapshot original extent observes exact completed writer and refuses equal foreign receipt" {
  let source = export_fixture(capture_fixture())
  let (stream, receipt) = snapshot_export_fixture(source)
  let (other, equal) = snapshot_export_fixture(source)
  // Existing independent rows are37 UTF-8 bytes,7 value nodes,2 rows,depth2;
  // logical wrapper adds28 bytes,2 nodes and one container, not policy depth20.
  assert_eq(
    completed_relation_export_snapshot_extent(stream, receipt).unwrap(),
    (65, 9, 2, 3),
  )
  assert_eq(
    completed_relation_export_snapshot_extent(other, equal).unwrap(),
    (65, 9, 2, 3),
  )
  assert_true(
    completed_relation_export_snapshot_extent(stream, equal)
    is Err(ForeignMaterial),
  )
  assert_true(
    completed_relation_export_snapshot_extent(other, receipt)
    is Err(ForeignMaterial),
  )
  cancel_completed_relation_export_receipt(receipt)
  assert_true(
    completed_relation_export_snapshot_extent(stream, receipt)
    is Err(NotFinished),
  )
  cancel_completed_relation_export_receipt(equal)
}

///|
test "snapshot preparation preserves exact wire and fields across quanta" {
  let source = export_fixture(capture_fixture())
  let (stream, receipt) = snapshot_export_fixture(source)
  for quantum in [1, 7, 64] {
    let preparation = start_completed_relation_export_snapshot(
      stream, receipt, 37, 7, 2, 100,
    ).unwrap()
    assert_true(preparation.finish() is Err(NotFinished))
    assert_eq(
      snapshot_finish(preparation, quantum).unwrap(),
      ("[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]", ["s", "n"]),
    )
    assert_eq(preparation.workspace.live, 0)
    assert_true(preparation.finish() is Err(Closed))
    preparation.cancel()
    preparation.cancel()
    assert_true(completed_output_available(source))
  }
  // Independent payload cost: 37 UTF-8 bytes, seven nodes, two containers.
  for (bytes, nodes, depth) in [(36, 7, 2), (37, 6, 2), (37, 7, 1)] {
    let preparation = start_completed_relation_export_snapshot(
      stream, receipt, bytes, nodes, depth, 100,
    ).unwrap()
    assert_true(
      snapshot_finish(preparation, 1) is Err(Wire(Encoding(OutputLimit))),
    )
    assert_eq(preparation.workspace.live, 0)
    assert_true(preparation.rows is None && preparation.receipt is None)
  }
  assert_true(completed_relation_export_matches_output(receipt, source))
  cancel_completed_relation_export_receipt(receipt)
}

///|
test "snapshot preparation bounds its field inventory before append" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false},\"s\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"v\"},{\"select\":[\"s\",\"n\"]}]",
  )
  let source = export_fixture(owner)
  let (stream, receipt) = snapshot_export_fixture(source)
  // Four fixed custody entries and two field-name references; no cell frames.
  let exact = start_completed_relation_export_snapshot(
    stream, receipt, 2, 1, 1, 6,
  ).unwrap()
  assert_eq(snapshot_finish(exact, 1).unwrap(), ("[]", ["s", "n"]))
  assert_eq(exact.workspace.peak, 6)
  assert_eq(exact.workspace.live, 0)
  let short = start_completed_relation_export_snapshot(
    stream, receipt, 2, 1, 1, 5,
  ).unwrap()
  assert_true(snapshot_finish(short, 1) is Err(Admission(CaptureLimit)))
  assert_eq(short.workspace.peak, 5)
  assert_eq(short.workspace.live, 0)
  assert_true(short.fields.is_empty())
  cancel_completed_relation_export_receipt(receipt)
}

///|
test "snapshot cancellation returns private custody without revoking its receipt" {
  let source = export_fixture(capture_fixture())
  let (stream, receipt) = snapshot_export_fixture(source)
  for stop in 0..<40 {
    let preparation = start_completed_relation_export_snapshot(
      stream, receipt, 1000, 100, 20, 100,
    ).unwrap()
    for _ in 0..<stop {
      if preparation.advance(1).unwrap().0 {
        break
      }
    }
    preparation.cancel()
    preparation.cancel()
    assert_true(preparation.advance(1) is Err(Closed))
    assert_true(preparation.finish() is Err(Closed))
    assert_true(preparation.rows is None && preparation.order is None)
    assert_true(preparation.receipt is None && preparation.wire is None)
    assert_eq(preparation.workspace.live, 0)
    assert_true(completed_relation_export_matches_output(receipt, source))
  }
  let revoked = start_completed_relation_export_snapshot(
    stream, receipt, 1000, 100, 20, 100,
  ).unwrap()
  assert_false(revoked.advance(1).unwrap().0)
  cancel_completed_relation_export_receipt(receipt)
  assert_true(revoked.advance(1) is Err(Closed))
  assert_eq(revoked.workspace.live, 0)
}

///|
test "snapshot yields inside a long Text cell and rejects a foreign receipt" {
  let text = String::make(129, 'é')
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false},\"s\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"n\":1,\"s\":\"" +
    text +
    "\"}]},\"as\":\"v\"},{\"select\":[\"s\",\"n\"]}]",
  )
  let source = export_fixture(owner)
  // The synchronous fixture export's batch must hold its complete Text cell;
  // the snapshot being tested still advances one bounded child step per poll.
  let (stream, receipt) = snapshot_export_fixture(source, max_batch_bytes=1024)
  let (_, foreign) = snapshot_export_fixture(source, max_batch_bytes=1024)
  assert_true(
    start_completed_relation_export_snapshot(
      stream, foreign, 1000, 100, 20, 100,
    )
    is Err(ForeignMaterial),
  )
  let preparation = start_completed_relation_export_snapshot(
    stream, receipt, 1000, 100, 20, 100,
  ).unwrap()
  let mut cells = 0
  for _ in 0..<1000 {
    let (done, used) = preparation.advance(1).unwrap()
    assert_true(used <= 1)
    if preparation.phase is Cell(_) {
      cells += 1
    }
    if done {
      break
    }
  }
  assert_true(cells >= 3)
  assert_eq(
    preparation.finish().unwrap(),
    ("[{\"n\":1,\"s\":\"" + text + "\"}]", ["s", "n"]),
  )
  cancel_completed_relation_export_receipt(receipt)
  cancel_completed_relation_export_receipt(foreign)
}
