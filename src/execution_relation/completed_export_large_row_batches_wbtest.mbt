///|
fn funded_large_row_fixture(
  cap : Int,
  available? : Ref[Bool] = Ref(true),
  name? : String = "s",
) -> (CompletedOutput, CompletedOutputExport, String) raise {
  // JSON escapes and multibyte UTF-8 cross bounded Text cursor transitions.
  let text_wire = String::make(2048, 'a') + "é😀\\n\\\\\\\""
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"" +
    name +
    "\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"" +
    name +
    "\":\"" +
    text_wire +
    "\"}]},\"as\":\"v\"},{\"select\":[\"" +
    name +
    "\"]}]",
  )
  let source = restrict_completed_output(export_fixture(owner), () => {
    available.val
  })
  let stream = prepare_completed_output_export(
    source,
    1,
    stream_value_limits(),
    { ..row_wire_limits(), max_bytes: 8192, },
    cap,
  ).unwrap()
  (source, stream, "[{\"" + name + "\":\"" + text_wire + "\"}]")
}

///|
test "funded physical batches split one Unicode row with one full row grant and identical canonical identity" {
  for quantum in [1, 7, 64] {
    let (source, stream, expected) = funded_large_row_fixture(
      1024,
      name=String::make(128, 'k'),
    )
    let grants = Ref(0)
    let requested = Ref(0)
    let before_payload = Ref(-1)
    let text = StringBuilder()
    let mut chunks = 0
    let mut mid_row = false
    let mut complete = false
    for _ in 0..<10000 {
      let next = advance_completed_output_export(
        stream,
        quantum,
        4,
        batch=true,
        before_batch_growth=Some(fn(bytes) {
          grants.val += 1
          requested.val = bytes
          before_payload.val = @encode.observed_writer_usage(stream.writer).0
          Ok(true)
        }),
      ).unwrap()
      assert_true(next.steps <= quantum)
      if next.batch is Some(part) {
        assert_true(!part.is_empty() && @utf8.encode(part).length() <= 1024)
        text.write_string(part)
        chunks += 1
        mid_row = mid_row || stream.row == 0
      }
      if next.complete {
        complete = true
        break
      }
    }
    assert_true(complete && mid_row && chunks >= 3)
    assert_eq(grants.val, 1)
    assert_true(requested.val > 1024 && requested.val < 8192)
    assert_eq(before_payload.val, 1)
    let (receipt, tail) = finish_completed_output_export(stream).unwrap()
    text.write_string(tail)
    assert_eq(text.to_string(), expected)
    assert_eq(receipt.content.cid, "sha256:" + @sha.hex(@utf8.encode(expected)))
    assert_true(completed_output_available(source))
    cancel_completed_export_receipt(receipt)
  }
}

///|
test "funded oversized row refuses the full grant before payload rather than clipping it to frame size" {
  let (source, stream, _) = funded_large_row_fixture(1024)
  let grants = Ref(0)
  let requested = Ref(0)
  let mut refused = false
  for _ in 0..<10000 {
    match
      advance_completed_output_export(
        stream,
        7,
        4,
        batch=true,
        before_batch_growth=Some(fn(bytes) {
          grants.val += 1
          requested.val = bytes
          Ok(false)
        }),
      ) {
      Ok(next) => assert_true(next.batch is None)
      Err(Admission(CaptureLimit)) => {
        refused = true
        break
      }
      Err(_) => fail("unexpected full row grant refusal")
    }
  }
  assert_true(refused)
  assert_eq(grants.val, 1)
  assert_true(requested.val > 1024)
  assert_eq(@encode.observed_writer_usage(stream.writer).0, 1)
  assert_true(stream.source is None && stream.pending_row is None)
  assert_true(completed_output_available(source))
}

///|
test "cancellation after a provisional oversized row fragment closes its same cursor without another grant" {
  let (source, stream, _) = funded_large_row_fixture(1024)
  let grants = Ref(0)
  let mut cancelled = false
  for _ in 0..<10000 {
    let next = advance_completed_output_export(
      stream,
      7,
      4,
      batch=true,
      before_batch_growth=Some(fn(_) {
        grants.val += 1
        Ok(true)
      }),
    ).unwrap()
    if next.batch is Some(_) {
      assert_eq(stream.row, 0)
      let cursor = stream.pending_row.unwrap()
      cancel_completed_output_export(stream)
      assert_true(cursor.closed && cursor.workspace.live == 0)
      assert_true(stream.source is None && stream.pending_row is None)
      assert_true(
        advance_completed_output_export(stream, 1, 4, batch=true) is Err(Closed),
      )
      assert_true(finish_completed_output_export(stream) is Err(Closed))
      cancelled = true
      break
    }
  }
  assert_true(cancelled && grants.val == 1)
  assert_true(completed_output_available(source))
}

///|
test "a physical frame smaller than one actual transition terminates with its typed encoding refusal" {
  let (source, stream, _) = funded_large_row_fixture(1)
  let grants = Ref(0)
  let mut refused = false
  for _ in 0..<10000 {
    match
      advance_completed_output_export(
        stream,
        7,
        4,
        batch=true,
        before_batch_growth=Some(fn(_) {
          grants.val += 1
          Ok(true)
        }),
      ) {
      Ok(next) => assert_true(next.batch is None)
      Err(Wire(Encoding(@encode.OutputLimit))) => {
        refused = true
        break
      }
      Err(_) => fail("unexpected tiny physical frame refusal")
    }
  }
  assert_true(refused && grants.val == 1)
  assert_true(stream.source is None && stream.pending_row is None)
  assert_true(completed_output_available(source))
}

///|
test "partial physical row drains preserve the original aggregate byte refusal" {
  let (source, unused, expected) = funded_large_row_fixture(1024)
  cancel_completed_output_export(unused)
  let stream = prepare_completed_output_export(
    source,
    1,
    stream_value_limits(),
    { ..row_wire_limits(), max_bytes: @utf8.encode(expected).length() - 2, },
    1024,
  ).unwrap()
  let mut refused = false
  for _ in 0..<10000 {
    match
      advance_completed_output_export(
        stream,
        7,
        4,
        batch=true,
        before_batch_growth=Some(fn(_) { Ok(true) }),
      ) {
      Ok(_) => ()
      Err(Wire(Encoding(@encode.OutputLimit))) => {
        refused = true
        break
      }
      Err(_) => fail("unexpected aggregate wire refusal")
    }
  }
  assert_true(refused && stream.source is None)
  assert_true(completed_output_available(source))
}

///|
test "revoked original availability between physical row fragments closes the same cursor" {
  let available = Ref(true)
  let (_, stream, _) = funded_large_row_fixture(1024, available~)
  let grants = Ref(0)
  let mut revoked = false
  for _ in 0..<10000 {
    let next = advance_completed_output_export(
      stream,
      7,
      4,
      batch=true,
      before_batch_growth=Some(fn(_) {
        grants.val += 1
        Ok(true)
      }),
    ).unwrap()
    if next.batch is Some(_) {
      let cursor = stream.pending_row.unwrap()
      available.val = false
      assert_true(
        advance_completed_output_export(stream, 1, 4, batch=true)
        is Err(Unavailable),
      )
      assert_true(cursor.closed && cursor.workspace.live == 0)
      assert_true(stream.source is None && stream.pending_row is None)
      revoked = true
      break
    }
  }
  assert_true(revoked && grants.val == 1)
}
