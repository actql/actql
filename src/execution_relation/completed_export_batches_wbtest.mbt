///|
fn physical_batch_fixture(cap : Int) -> CompletedOutputExport raise {
  prepare_completed_output_export(
    export_fixture(capture_fixture()),
    2,
    { ..stream_value_limits(), max_work: 16, },
    row_wire_limits(),
    cap,
  ).unwrap()
}

///|
test "physical export batches retain exact wire digest work and bounded backing across quanta" {
  for quantum in [1, 7, 64] {
    let stream = physical_batch_fixture(128)
    let text = StringBuilder()
    let mut batches = 0
    let mut work = 0
    let mut complete = false
    for _ in 0..<100 {
      let next = advance_completed_output_export(stream, quantum, 3, batch=true).unwrap()
      work += next.steps
      assert_eq(completed_output_export_poll_steps(stream), next.steps)
      assert_true(next.steps <= quantum)
      let held = @encode.observed_writer_usage(stream.writer).0 -
        stream.drained_bytes
      assert_true(held >= 0 && held <= 128)
      if next.batch is Some(part) {
        assert_true(@utf8.encode(part).length() <= 128)
        text.write_string(part)
        batches += 1
      }
      if next.complete {
        complete = true
        break
      }
    }
    assert_true(complete)
    assert_eq((batches, work), (1, 32))
    assert_eq(
      (stream.budget.nodes, stream.budget.text, stream.budget.work),
      (6, 10, 16),
    )
    let (receipt, tail) = finish_completed_output_export(stream).unwrap()
    assert_eq(tail, "]")
    text.write_string(tail)
    assert_eq(
      text.to_string(),
      "[{\"n\":1,\"s\":\"é\"},{\"n\":2,\"s\":\"😀\"}]",
    )
    assert_eq(
      receipt.content.cid,
      "sha256:1f3a78f3ede9a4385bbcbf098a3f0fdb9b16dc3e0e8d78f05255682d9c25f3e0",
    )
    cancel_completed_export_receipt(receipt)
  }
}

///|
test "conservative physical row bound only drains earlier and preserves exact Unicode row limits" {
  for cap in [20, 32] {
    let stream = physical_batch_fixture(cap)
    let parts : Array[String] = []
    while next_completed_output_export(stream, batch=true).unwrap()
          is Some(part) {
      assert_true(@utf8.encode(part).length() <= cap)
      parts.push(part)
    }
    assert_eq(parts, ["[{\"n\":1,\"s\":\"é\"}", ",{\"n\":2,\"s\":\"😀\"}"])
    let (receipt, tail) = finish_completed_output_export(stream).unwrap()
    assert_eq(tail, "]")
    assert_eq(
      receipt.content.cid,
      "sha256:1f3a78f3ede9a4385bbcbf098a3f0fdb9b16dc3e0e8d78f05255682d9c25f3e0",
    )
    cancel_completed_export_receipt(receipt)
  }
  for batched in [false, true] {
    let stream = physical_batch_fixture(16)
    assert_true(
      next_completed_output_export(stream, batch=batched)
      is Err(Wire(Encoding(@encode.OutputLimit))),
    )
    assert_true(stream.source is None && stream.pending_row is None)
    assert_true(finish_completed_output_export(stream) is Err(Closed))
  }
}

///|
test "physical export conservative key bound preserves escaped Unicode rows that actually fit" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"é\\\"\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"é\\\"\":\"\\n\"},{\"é\\\"\":\"\\\\\\\"\"}]},\"as\":\"v\"},{\"select\":[\"é\\\"\"]}]",
  )
  for batched in [false, true] {
    let stream = prepare_completed_output_export(
      export_fixture(owner),
      2,
      stream_value_limits(),
      row_wire_limits(),
      20,
    ).unwrap()
    let text = StringBuilder()
    while next_completed_output_export(stream, batch=batched).unwrap()
          is Some(part) {
      assert_true(@utf8.encode(part).length() <= 20)
      text.write_string(part)
    }
    let (receipt, tail) = finish_completed_output_export(stream).unwrap()
    text.write_string(tail)
    assert_eq(
      text.to_string(),
      "[{\"é\\\"\":\"\\n\"},{\"é\\\"\":\"\\\\\\\"\"}]",
    )
    cancel_completed_export_receipt(receipt)
  }
}

///|
test "physical export cannot switch the existing canonical row reader mode" {
  let row = physical_batch_fixture(128)
  let first = next_completed_output_export_canonical_row(row, 100, 10, 100)
    .unwrap()
    .unwrap()
  assert_eq(first.0, 0)
  assert_eq(first.1, "[{\"n\":1,\"s\":\"é\"}")
  assert_true(next_completed_output_export(row, batch=true) is Err(Closed))
  let batched = physical_batch_fixture(128)
  advance_completed_output_export(batched, 1, 3, batch=true).unwrap() |> ignore
  assert_true(
    next_completed_output_export_canonical_row(batched, 100, 10, 100)
    is Err(Closed),
  )
}

///|
test "physical export keeps row availability before the next row inside one batch" {
  let source = export_fixture(capture_fixture())
  let original : Ref[CompletedOutputExport?] = Ref(None)
  let restricted = restrict_completed_output(source, fn() {
    original.val.map(stream => stream.row == 0).unwrap_or(true)
  })
  let stream = prepare_completed_output_export(
    restricted,
    2,
    stream_value_limits(),
    row_wire_limits(),
    128,
  ).unwrap()
  original.val = Some(stream)
  assert_true(
    advance_completed_output_export(stream, 64, 3, batch=true)
    is Err(Unavailable),
  )
  assert_true(stream.source is None && stream.pending_row is None)
  assert_true(completed_output_available(source))
}

///|
test "physical export preserves workspace work failure and cancellation without finalization" {
  for (work, slots) in [(15, 3), (16, 2)] {
    let source = export_fixture(capture_fixture())
    let stream = prepare_completed_output_export(
      source,
      2,
      { ..stream_value_limits(), max_work: work, },
      row_wire_limits(),
      128,
    ).unwrap()
    let mut failed = false
    for _ in 0..<100 {
      match advance_completed_output_export(stream, 7, slots, batch=true) {
        Err(Admission(CaptureLimit)) => {
          failed = true
          break
        }
        Err(_) => fail("original work or workspace refusal")
        Ok(next) => assert_false(next.complete)
      }
    }
    assert_true(failed)
    assert_true(stream.source is None && stream.pending_row is None)
    assert_true(finish_completed_output_export(stream) is Err(Closed))
    assert_true(completed_output_available(source))
  }
  let stream = physical_batch_fixture(128)
  advance_completed_output_export(stream, 7, 3, batch=true).unwrap() |> ignore
  cancel_completed_output_export(stream)
  assert_true(stream.pending_row is None)
  assert_true(finish_completed_output_export(stream) is Err(Closed))
}
