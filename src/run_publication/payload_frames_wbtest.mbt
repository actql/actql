///|
test "durable Result row frame backing follows admitted total bytes" {
  let payload = b"[{\"id\":1}]"
  let frames = prepare_durable_result_row_frames(
    payload.length(),
    1,
    1048576,
    8,
    32,
  ).unwrap()
  // Count the actual initialized slots, not allocator bytes or process RSS.
  assert_eq(frames.row.length(), payload.length())
  assert_eq(frames.max_row_bytes, 1048576)
  assert_eq(feed_durable_result_row_frames(frames, b"[{\"id\":"), Ok([]))
  assert_eq(feed_durable_result_row_frames(frames, b"1}]"), Ok(["{\"id\":1}"]))
  assert_eq(
    finish_durable_result_row_frames(frames),
    Ok({ bytes: payload.length(), rows: 1, }),
  )
  let smaller_row = prepare_durable_result_row_frames(1024, 1, 3, 2, 32).unwrap()
  assert_eq(smaller_row.row.length(), 3)
  assert_true(
    feed_durable_result_row_frames(smaller_row, payload)
    is Err(DurableRowFrameRowSizeLimit),
  )
}

///|
test "durable Result row frame backing preserves zero byte and original refusal guards" {
  let zero = prepare_durable_result_row_frames(0, 1, 1048576, 8, 32).unwrap()
  assert_eq(zero.row.length(), 0)
  assert_eq(zero.max_row_bytes, 1048576)
  assert_eq(feed_durable_result_row_frames(zero, b""), Ok([]))
  assert_true(
    feed_durable_result_row_frames(zero, b"[") is Err(DurableRowFrameByteLimit),
  )
  let empty = prepare_durable_result_row_frames(2, 0, 1048576, 8, 32).unwrap()
  assert_eq(empty.row.length(), 2)
  assert_eq(feed_durable_result_row_frames(empty, b"[]"), Ok([]))
  assert_eq(finish_durable_result_row_frames(empty), Ok({ bytes: 2, rows: 0, }))
  let truncated = prepare_durable_result_row_frames(3, 1, 1048576, 8, 32).unwrap()
  assert_eq(truncated.row.length(), 3)
  assert_eq(feed_durable_result_row_frames(truncated, b"["), Ok([]))
  assert_eq(feed_durable_result_row_frames(truncated, b"{"), Ok([]))
  assert_eq(feed_durable_result_row_frames(truncated, b"}"), Ok(["{}"]))
  assert_true(
    feed_durable_result_row_frames(truncated, b"]")
    is Err(DurableRowFrameByteLimit),
  )
  for invalid in [0, 16777217] {
    // A small actual payload cannot mask an invalid configured row ceiling.
    assert_true(
      prepare_durable_result_row_frames(2, 0, invalid, 8, 32)
      is Err(DurableRowFrameInvalidLimits),
    )
  }
}
