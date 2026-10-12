///|
test "row export preserves independent work bytes and ordered identity across quanta" {
  for quantum in [1, 7, 64] {
    let source = export_fixture(capture_fixture())
    let stream = prepare_completed_output_export(
      source,
      2,
      { ..stream_value_limits(), max_work: 16, },
      row_wire_limits(),
      64,
    ).unwrap()
    let text = StringBuilder()
    let mut steps = 0
    let mut complete = false
    for _ in 0..<100 {
      let poll = advance_completed_output_export(stream, quantum, 3).unwrap()
      assert_true(poll.steps <= quantum)
      assert_eq(completed_output_export_poll_steps(stream), poll.steps)
      steps += poll.steps
      if poll.batch is Some(batch) {
        text.write_string(batch)
      }
      if poll.complete {
        complete = true
        break
      }
    }
    assert_true(complete)
    assert_true(completed_output_export_rows_complete(stream).unwrap())
    assert_eq(completed_output_export_poll_steps(stream), 0)
    // Each row: ten admission/measurement transitions, then six emission
    // transitions. Logical work is six nodes plus ten UTF-8 Text bytes.
    assert_eq(steps, 32)
    assert_eq(
      (stream.budget.nodes, stream.budget.text, stream.budget.work),
      (6, 10, 16),
    )
    let (receipt, tail) = finish_completed_output_export(stream).unwrap()
    text.write_string(tail)
    assert_eq(
      text.to_string(),
      "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]",
    )
    assert_eq(
      receipt.content.cid,
      "sha256:1f3a78f3ede9a4385bbcbf098a3f0fdb9b16dc3e0e8d78f05255682d9c25f3e0",
    )
    assert_true(stream.pending_row is None)
    assert_true(completed_output_available(source))
    cancel_completed_export_receipt(receipt)
  }
}

///|
test "row export rejects independent one short work and workspace without completing" {
  for (work, slots) in [(15, 3), (16, 2)] {
    let source = export_fixture(capture_fixture())
    let stream = prepare_completed_output_export(
      source,
      2,
      { ..stream_value_limits(), max_work: work, },
      row_wire_limits(),
      64,
    ).unwrap()
    let mut rejected = false
    for _ in 0..<100 {
      match advance_completed_output_export(stream, 1, slots) {
        Err(Admission(CaptureLimit)) => {
          // Both nested-workspace refusal and the one-short value budget
          // occur inside an entered frame, even though cleanup clears it.
          assert_eq(completed_output_export_poll_steps(stream), 1)
          let failed_steps = completed_output_export_poll_steps(stream)
          cancel_completed_output_export(stream)
          assert_eq(completed_output_export_poll_steps(stream), failed_steps)
          rejected = true
          break
        }
        Err(_) => fail("unexpected export failure")
        Ok(poll) => assert_false(poll.complete)
      }
    }
    assert_true(rejected)
    assert_true(stream.source is None && stream.pending_row is None)
    assert_true(completed_output_export_rows_complete(stream) is Err(Closed))
    assert_true(finish_completed_output_export(stream) is Err(Closed))
    assert_true(completed_output_available(source))
    assert_true(
      advance_completed_output_export(stream, 1, slots) is Err(Closed),
    )
    assert_eq(completed_output_export_poll_steps(stream), 0)
  }
}

///|
test "row export cancellation and revocation clear private roots not the producer" {
  for revoke in [false, true] {
    for stop in [1, 3, 12, 15, 17, 31] {
      let source = export_fixture(capture_fixture())
      let permission = Ref(true)
      let restricted = restrict_completed_output(source, fn() { permission.val })
      let stream = prepare_completed_output_export(
        restricted,
        2,
        stream_value_limits(),
        row_wire_limits(),
        64,
      ).unwrap()
      for _ in 0..<stop {
        advance_completed_output_export(stream, 1, 3).unwrap() |> ignore
      }
      let cursor = stream.pending_row.unwrap()
      assert_true(cursor.workspace.live > 0)
      if revoke {
        permission.val = false
        assert_true(
          advance_completed_output_export(stream, 1, 3) is Err(Unavailable),
        )
      } else {
        cancel_completed_output_export(stream)
        assert_true(
          advance_completed_output_export(stream, 1, 3) is Err(Closed),
        )
      }
      cancel_completed_output_export(stream)
      assert_eq(cursor.workspace.live, 0)
      assert_true(cursor.closed && stream.pending_row is None)
      assert_true(finish_completed_output_export(stream) is Err(Closed))
      assert_true(completed_output_available(source))
    }
  }
}

///|
test "row export yields within long Unicode Text before handing a complete batch" {
  let text = String::make(1024, 'a') + "😀"
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"s\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"s\":\"" +
    text +
    "\"}]},\"as\":\"v\"},{\"select\":[\"s\"]}]",
  )
  let source = export_fixture(owner)
  let stream = prepare_completed_output_export(
    source,
    1,
    { max_nodes: 2, max_work: 1031, max_text_bytes: 1029, max_depth: 2, },
    { ..row_wire_limits(), max_bytes: 2048, },
    2048,
  ).unwrap()
  let mut yielded = 0
  let mut batch : String? = None
  for _ in 0..<200 {
    let poll = advance_completed_output_export(stream, 1, 4).unwrap()
    assert_eq(poll.steps, 1)
    if poll.batch is Some(value) {
      batch = Some(value)
      break
    }
    yielded += 1
    assert_eq(stream.row, 0)
  }
  assert_true(yielded > 32)
  assert_eq(batch.unwrap(), "[{\"s\":\"" + text + "\"}")
  assert_eq(stream.budget.work, 1031)
  assert_true(advance_completed_output_export(stream, 1, 4).unwrap().complete)
  let (receipt, tail) = finish_completed_output_export(stream).unwrap()
  assert_eq(tail, "]")
  cancel_completed_export_receipt(receipt)
}

///|
test "row export polls nested admission and wire with exact independent boundaries" {
  let items = Array::make(500, "0").join(",")
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":[{\"payload\":[" +
    items +
    "]}]},\"as\":\"v\"},{\"select\":[\"payload\"],\"as\":\"selected\"}]",
  )
  let source = export_fixture(owner)
  // One row + one array + 500 numbers = 502 nodes. The seven-byte key
  // makes 509 work. Existing wire custody needs six entries, plus our owner.
  for
    (work, slots, cancel) in [
      (509, 7, false),
      (508, 7, false),
      (509, 6, false),
      (509, 7, true),
    ] {
    let stream = prepare_completed_output_export(
      source,
      1,
      { max_nodes: 502, max_work: work, max_text_bytes: 7, max_depth: 3, },
      { ..row_wire_limits(), max_bytes: 2048, max_nodes: 504, },
      2048,
    ).unwrap()
    let text = StringBuilder()
    let mut terminal = false
    let mut rejected = false
    for poll in 0..<4000 {
      if cancel && poll == 100 {
        let cursor = stream.pending_row.unwrap()
        assert_true(cursor.phase is MeasureCell(_))
        cancel_completed_output_export(stream)
        assert_eq(cursor.workspace.live, 0)
        assert_true(
          advance_completed_output_export(stream, 1, slots) is Err(Closed),
        )
        terminal = true
        break
      }
      match advance_completed_output_export(stream, 1, slots) {
        Err(Admission(CaptureLimit)) => {
          rejected = true
          terminal = true
          break
        }
        Err(_) => fail("unexpected nested export failure")
        Ok(result) => {
          if result.batch is Some(batch) {
            text.write_string(batch)
          }
          if result.complete {
            terminal = true
            break
          }
        }
      }
    }
    assert_true(terminal)
    assert_eq(rejected, work == 508 || slots == 6)
    if !cancel && !rejected {
      let (receipt, tail) = finish_completed_output_export(stream).unwrap()
      text.write_string(tail)
      assert_eq(text.to_string(), "[{\"payload\":[" + items + "]}]")
      assert_eq(stream.budget.work, 509)
      cancel_completed_export_receipt(receipt)
    } else {
      assert_true(finish_completed_output_export(stream) is Err(Closed))
    }
    assert_true(stream.pending_row is None)
    assert_true(completed_output_available(source))
  }
}

///|
test "row export resumes long ordered keys and reclaims an interrupted key" {
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
  for cancel in [false, true] {
    let stream = prepare_completed_output_export(
      source,
      1,
      { max_nodes: 2, max_work: 258, max_text_bytes: 256, max_depth: 2, },
      { ..row_wire_limits(), max_bytes: 1024, },
      1024,
    ).unwrap()
    let mut batch : String? = None
    let mut key_polls = 0
    for _ in 0..<100 {
      let result = advance_completed_output_export(stream, 1, 3).unwrap()
      if stream.pending_row is Some(cursor) && cursor.phase is EmitKey(_, _) {
        key_polls += 1
        if cancel && key_polls == 2 {
          cancel_completed_output_export(stream)
          assert_eq(cursor.workspace.live, 0)
          break
        }
      }
      if result.batch is Some(value) {
        batch = Some(value)
        break
      }
    }
    assert_true(key_polls >= 2)
    if cancel {
      assert_true(batch is None && stream.pending_row is None)
      assert_true(finish_completed_output_export(stream) is Err(Closed))
    } else {
      assert_eq(batch.unwrap(), "[{\"" + name + "\":null}")
      let (receipt, tail) = finish_completed_output_export(stream).unwrap()
      assert_eq(tail, "]")
      cancel_completed_export_receipt(receipt)
    }
    assert_true(completed_output_available(source))
  }
}
