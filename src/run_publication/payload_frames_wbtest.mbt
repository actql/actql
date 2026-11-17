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
  for invalid in [0, -1] {
    // A small actual payload cannot mask an invalid configured row ceiling.
    assert_true(
      prepare_durable_result_row_frames(2, 0, invalid, 8, 32)
      is Err(DurableRowFrameInvalidLimits),
    )
  }
}

///|
test "growing Result frames keep policy distinct from actual row backing and preserve byte structure" {
  let frames = prepare_growing_durable_result_row_frames(
    20000000, 2, 19000000, 8, 64,
  ).unwrap()
  assert_eq(frames.row.length(), 32)
  assert_eq(frames.max_row_bytes, 19000000)
  let prefix = b"[{\"value\":\""
  feed_durable_result_row_frames(frames, prefix).unwrap() |> ignore
  let chunk = @utf8.encode("x".repeat(60))
  let next = durable_result_row_frame_growth(frames, chunk.length()).unwrap()
  assert_true(next >= prefix.length() - 1 + chunk.length())
  assert_eq(frames.row.length(), 32, msg="Demand projection allocates nothing")
  grow_durable_result_row_frame_buffer(frames, next).unwrap()
  feed_durable_result_row_frames(frames, chunk).unwrap() |> ignore
  let suffix = b"\"}]"
  let next = durable_result_row_frame_growth(frames, suffix.length()).unwrap()
  grow_durable_result_row_frame_buffer(frames, next).unwrap()
  assert_eq(
    feed_durable_result_row_frames(frames, suffix),
    Ok(["{\"value\":\"" + "x".repeat(60) + "\"}"]),
  )
  assert_eq(finish_durable_result_row_frames(frames).unwrap().rows, 1)
  assert_true(
    grow_durable_result_row_frame_buffer(frames, next)
    is Err(DurableRowFrameClosed),
  )
  let explicit = prepare_durable_result_row_frames(4, 1, 16777217, 8, 32).unwrap()
  assert_eq(explicit.row.length(), 4)
  assert_eq(feed_durable_result_row_frames(explicit, b"[{}]"), Ok(["{}"]))
}
