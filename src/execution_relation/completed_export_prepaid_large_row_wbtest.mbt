///|
test "ordinary physical batch next splits an oversized row without a dynamic grow callback" {
  let (source, stream, expected) = funded_large_row_fixture(
    1024,
    name=String::make(128, 'k'),
  )
  let text = StringBuilder()
  let mut chunks = 0
  let mut mid_row = false
  let mut complete = false
  for _ in 0..<10000 {
    // This is the exact next(batch=true) entrance used by publication. Its
    // caller owns the already admitted output and fixed export workspace;
    // absence of a numerical growth callback does not enlarge a frame.
    match next_completed_output_export(stream, batch=true).unwrap() {
      Some(part) => {
        assert_true(!part.is_empty() && @utf8.encode(part).length() <= 1024)
        text.write_string(part)
        chunks += 1
        mid_row = mid_row || stream.row == 0
      }
      None => {
        complete = true
        break
      }
    }
  }
  assert_true(complete && mid_row && chunks >= 3)
  let (receipt, tail) = finish_completed_output_export(stream).unwrap()
  text.write_string(tail)
  assert_eq(text.to_string(), expected)
  assert_eq(receipt.content.cid, "sha256:" + @sha.hex(@utf8.encode(expected)))
  assert_eq(receipt.content.bytes, @utf8.encode(expected).length())
  assert_true(completed_output_available(source))
  cancel_completed_export_receipt(receipt)
}

///|
test "ordinary fragmented physical next preserves aggregate limits and current refusal" {
  for revoked in [false, true] {
    let available = Ref(true)
    let (source, unused, expected) = funded_large_row_fixture(1024, available~)
    cancel_completed_output_export(unused)
    let stream = prepare_completed_output_export(
      source,
      1,
      stream_value_limits(),
      {
        ..row_wire_limits(),
        max_bytes: if revoked {
          8192
        } else {
          @utf8.encode(expected).length() - 2
        },
      },
      1024,
    ).unwrap()
    let first = next_completed_output_export(stream, batch=true)
      .unwrap()
      .unwrap()
    assert_true(!first.is_empty() && @utf8.encode(first).length() <= 1024)
    assert_eq(stream.row, 0)
    let cursor = stream.pending_row.unwrap()
    if revoked {
      available.val = false
      assert_true(
        next_completed_output_export(stream, batch=true) is Err(Unavailable),
      )
    } else {
      let mut refused = false
      for _ in 0..<10000 {
        match next_completed_output_export(stream, batch=true) {
          Ok(_) => ()
          Err(Wire(Encoding(@encode.OutputLimit))) => {
            refused = true
            break
          }
          Err(_) => fail("unexpected aggregate output refusal")
        }
      }
      assert_true(refused)
    }
    assert_true(cursor.closed && cursor.workspace.live == 0)
    assert_true(stream.source is None && stream.pending_row is None)
    assert_true(finish_completed_output_export(stream) is Err(Closed))
  }
}
