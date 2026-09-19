///|
test "durable Result row frames preserve rows across physical chunks" {
  let frames = prepare_durable_result_row_frames(128, 2, 64, 8, 32).unwrap()
  assert_eq(feed_durable_result_row_frames(frames, b"[{\"a\":"), Ok([]))
  assert_eq(
    feed_durable_result_row_frames(frames, b"[1,{\"b\":\"]\"}]}"),
    Ok(["{\"a\":[1,{\"b\":\"]\"}]}"]),
  )
  assert_eq(
    feed_durable_result_row_frames(frames, b",{\"a\":[]}]"),
    Ok(["{\"a\":[]}"]),
  )
  assert_eq(
    finish_durable_result_row_frames(frames),
    Ok({ bytes: 30, rows: 2, }),
  )
  assert_true(
    feed_durable_result_row_frames(frames, b"") is Err(DurableRowFrameClosed),
  )
}

///|
test "durable Result row frames accept an empty canonical payload" {
  let frames = prepare_durable_result_row_frames(2, 0, 1, 1, 2).unwrap()
  assert_eq(feed_durable_result_row_frames(frames, b"[]"), Ok([]))
  assert_eq(
    finish_durable_result_row_frames(frames),
    Ok({ bytes: 2, rows: 0, }),
  )
}

///|
test "durable Result row frames reject structure and capacity violations" {
  let invalid = prepare_durable_result_row_frames(8, 1, 4, 1, 8).unwrap()
  assert_true(
    feed_durable_result_row_frames(invalid, b"{}")
    is Err(DurableRowFrameInvalidArray),
  )
  let row_limit = prepare_durable_result_row_frames(16, 0, 8, 1, 16).unwrap()
  assert_true(
    feed_durable_result_row_frames(row_limit, b"[{}]")
    is Err(DurableRowFrameRowLimit),
  )
  let row_size = prepare_durable_result_row_frames(16, 1, 1, 2, 16).unwrap()
  assert_true(
    feed_durable_result_row_frames(row_size, b"[{}]")
    is Err(DurableRowFrameRowSizeLimit),
  )
  let depth = prepare_durable_result_row_frames(16, 1, 8, 1, 16).unwrap()
  assert_true(
    feed_durable_result_row_frames(depth, b"[{\"a\":[]}]")
    is Err(DurableRowFrameDepthLimit),
  )
  let frame = prepare_durable_result_row_frames(16, 1, 8, 2, 2).unwrap()
  assert_true(
    feed_durable_result_row_frames(frame, b"[{}]")
    is Err(DurableRowFrameByteLimit),
  )
}

///|
test "durable Result row frames reject invalid UTF-8 and incomplete input" {
  let invalid = prepare_durable_result_row_frames(8, 1, 6, 2, 8).unwrap()
  assert_true(
    feed_durable_result_row_frames(
      invalid,
      Bytes::from_array([0x5B, 0x7B, 0x22, 0xC0, 0x22, 0x7D, 0x5D]),
    )
    is Err(DurableRowFrameInvalidUtf8),
  )
  let incomplete = prepare_durable_result_row_frames(8, 1, 6, 2, 8).unwrap()
  assert_eq(feed_durable_result_row_frames(incomplete, b"[{}"), Ok(["{}"]))
  assert_true(
    finish_durable_result_row_frames(incomplete)
    is Err(DurableRowFrameIncomplete),
  )
}
