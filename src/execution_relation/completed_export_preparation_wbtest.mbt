///|
test "completed export metadata owns incremental arrays with independent exact bounds" {
  for quantum in [1, 7, 64] {
    let source = export_fixture(capture_fixture())
    let cursor = start_completed_output_export(
      source,
      2,
      stream_value_limits(),
      { ..row_wire_limits(), max_columns: 2, max_order_work: 5, },
      64,
      32,
    ).unwrap()
    assert_eq(cursor.rows.unwrap().names, ["s", "n"])
    assert_true(cursor.names.is_empty() && cursor.column_rows.is_empty())
    assert_true(
      finish_completed_output_export_preparation(cursor) is Err(NotFinished),
    )
    let mut steps = 0
    for _ in 0..<100 {
      let (done, used) = advance_completed_output_export_preparation(
        cursor, quantum,
      ).unwrap()
      assert_true(used <= quantum)
      assert_eq(cursor.poll_work, used)
      steps += used
      if done {
        break
      }
    }
    // Sixteen order frames, two column initializations, the end check and
    // constant writer initialization. Slots: 16 fixed + 2*(1 order + 7 metadata).
    assert_eq(steps, 20)
    assert_eq(cursor.workspace.peak, 32)
    let stream = finish_completed_output_export_preparation(cursor).unwrap()
    assert_true(cursor.closed && cursor.rows is None && cursor.names.is_empty())
    assert_eq(cursor.workspace.live, 0)
    assert_true(
      finish_completed_output_export_preparation(cursor) is Err(Closed),
    )
    let text = StringBuilder()
    while next_completed_output_export(stream).unwrap() is Some(batch) {
      text.write_string(batch)
    }
    let (receipt, tail) = finish_completed_output_export(stream).unwrap()
    text.write_string(tail)
    assert_eq(
      text.to_string(),
      "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]",
    )
    assert_eq(
      completed_export_content(receipt).cid,
      "sha256:1f3a78f3ede9a4385bbcbf098a3f0fdb9b16dc3e0e8d78f05255682d9c25f3e0",
    )
    assert_true(completed_output_available(source))
    cancel_completed_export_receipt(receipt)
  }
}

///|
test "completed export metadata one-short refuses the typed capacity or order cause" {
  for (slots, order_work) in [(31, 5), (32, 4)] {
    let source = export_fixture(capture_fixture())
    let cursor = start_completed_output_export(
      source,
      2,
      stream_value_limits(),
      { ..row_wire_limits(), max_columns: 2, max_order_work: order_work, },
      64,
      slots,
    ).unwrap()
    let mut refused = false
    for _ in 0..<100 {
      match advance_completed_output_export_preparation(cursor, 1) {
        Err(Admission(CaptureLimit)) if slots == 31 => {
          refused = true
          break
        }
        Err(Wire(OrderLimit)) if order_work == 4 => {
          refused = true
          break
        }
        Ok((false, _)) => ()
        _ => fail("wrong one-short cause")
      }
    }
    assert_true(
      refused && cursor.closed && cursor.stream is None && cursor.rows is None,
    )
    assert_eq(cursor.workspace.live, 0)
    assert_true(completed_output_available(source))
  }
}

///|
test "failed metadata poll preserves order and column work before reclaiming its workspace" {
  let source = export_fixture(capture_fixture())
  let cursor = start_completed_output_export(
    source,
    2,
    stream_value_limits(),
    { ..row_wire_limits(), max_columns: 2, max_order_work: 5, },
    64,
    31,
  ).unwrap()
  assert_true(
    advance_completed_output_export_preparation(cursor, 64)
    is Err(Admission(CaptureLimit)),
  )
  // Sixteen order frames plus the two column-reservation frames. The second
  // reservation fails; its earlier work must not disappear with private arrays.
  assert_eq(cursor.poll_work, 18)
  assert_eq(cursor.workspace.live, 0)
  assert_true(cursor.closed && cursor.stream is None)
  assert_true(completed_output_available(source))
}

///|
test "completed export metadata cancellation retires preparation not producer" {
  for ticks in [1, 8, 16, 18, 19] {
    let source = export_fixture(capture_fixture())
    let cursor = start_completed_output_export(
      source,
      2,
      stream_value_limits(),
      row_wire_limits(),
      64,
      32,
    ).unwrap()
    for _ in 0..<ticks {
      advance_completed_output_export_preparation(cursor, 1).unwrap() |> ignore
    }
    assert_true(cancel_completed_output_export_preparation(cursor))
    assert_true(!cancel_completed_output_export_preparation(cursor))
    assert_eq(cursor.workspace.live, 0)
    assert_true(
      cursor.rows is None && cursor.stream is None && cursor.names.is_empty(),
    )
    assert_true(cursor.column_rows.is_empty() && cursor.order is None)
    assert_true(
      finish_completed_output_export_preparation(cursor) is Err(Closed),
    )
    assert_true(completed_output_available(source))
  }
}

///|
test "completed export metadata preserves zero rows and rechecks source before transfer" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false},\"s\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[]},\"as\":\"v\"},{\"select\":[\"s\",\"n\"]}]",
  )
  let source = export_fixture(owner)
  let cursor = start_completed_output_export(
    source,
    0,
    { max_nodes: 0, max_text_bytes: 0, max_depth: 0, max_work: 0, },
    row_wire_limits(),
    64,
    32,
  ).unwrap()
  for _ in 0..<30 {
    if advance_completed_output_export_preparation(cursor, 1).unwrap().0 {
      break
    }
  }
  let stream = finish_completed_output_export_preparation(cursor).unwrap()
  assert_eq(next_completed_output_export(stream).unwrap(), None)
  let (receipt, tail) = finish_completed_output_export(stream).unwrap()
  assert_eq(tail, "[]")
  assert_eq(
    completed_export_content(receipt).cid,
    "sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
  )
  cancel_completed_export_receipt(receipt)
  let permission = Ref(true)
  let restricted = restrict_completed_output(source, fn() { permission.val })
  let pending = start_completed_output_export(
    restricted,
    0,
    stream_value_limits(),
    row_wire_limits(),
    64,
    32,
  ).unwrap()
  for _ in 0..<30 {
    if advance_completed_output_export_preparation(pending, 1).unwrap().0 {
      break
    }
  }
  permission.val = false
  assert_true(
    finish_completed_output_export_preparation(pending) is Err(Unavailable),
  )
  assert_true(pending.closed && pending.stream is None && pending.rows is None)
  assert_eq(pending.workspace.live, 0)
  assert_true(completed_output_available(source))
}

///|
test "publication export transfers private summaries once and keeps public snapshots independent" {
  let source = export_fixture(capture_fixture())
  let stream = prepare_completed_relation_export(
    source,
    2,
    stream_value_limits(),
    row_wire_limits(),
    { ..row_wire_limits(), max_bytes: 1000, max_nodes: 100, max_depth: 20, },
    publication_schema_limits(),
    64,
  ).unwrap()
  while next_completed_output_export(stream).unwrap() is Some(_) {

  }
  let rows = stream.column_rows
  let bytes = stream.column_bytes
  let nodes = stream.column_nodes
  let maximum = stream.column_max_value_bytes
  let nulls = stream.column_null_rows
  let depths = stream.column_admitted_depths
  let (receipt, _) = finish_completed_relation_export(stream).unwrap()
  assert_true(physical_equal(receipt.measurement.column_rows, rows))
  assert_true(physical_equal(receipt.measurement.column_bytes, bytes))
  assert_true(physical_equal(receipt.measurement.column_nodes, nodes))
  assert_true(
    physical_equal(receipt.measurement.column_max_value_bytes, maximum),
  )
  assert_true(physical_equal(receipt.measurement.column_null_rows, nulls))
  assert_true(
    physical_equal(receipt.measurement.column_admitted_depths, depths),
  )
  assert_true(stream.column_rows.is_empty() && stream.column_bytes.is_empty())
  assert_true(
    stream.column_nodes.is_empty() && stream.column_max_value_bytes.is_empty(),
  )
  assert_true(
    stream.column_null_rows.is_empty() &&
    stream.column_admitted_depths.is_empty(),
  )
  assert_eq(receipt.measurement.column_rows, [2, 2])
  assert_eq(receipt.measurement.column_bytes, [2, 10])
  assert_eq(receipt.measurement.column_nodes, [2, 2])
  assert_eq(receipt.measurement.admission_work, 16)
  assert_true(finish_completed_relation_export(stream) is Err(Closed))
  let snapshot = completed_relation_export_measurement(receipt)
  snapshot.column_rows[0] = 99
  assert_eq(completed_relation_export_measurement(receipt).column_rows, [2, 2])
  let fields = completed_relation_export_field_names(receipt)
  fields.clear()
  assert_eq(completed_relation_export_field_names(receipt), ["s", "n"])
  cancel_completed_relation_export_receipt(receipt)
}
