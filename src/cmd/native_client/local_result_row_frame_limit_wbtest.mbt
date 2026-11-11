///|
test "selected Native Result output ceiling backs complete long rows without weakening a smaller ceiling" {
  assert_eq(local_result_row_frame_limit(16777216), 16777216)
  assert_eq(local_result_row_frame_limit(33554432), 16777216)
  assert_eq(local_result_row_frame_limit(32768), 32768)
  let row = "{\"text\":\"" + "a".repeat(524288) + "\"}"
  let payload = @utf8.encode("[" + row + "]")
  for admitted in [true, false] {
    let selected = if admitted { 16777216 } else { 32768 }
    let frames = @publication.prepare_durable_result_row_frames(
      payload.length(),
      1,
      local_result_row_frame_limit(selected),
      8,
      16384,
    ).unwrap()
    let mut offset = 0
    let rows : Array[String] = []
    let mut refused = false
    while offset < payload.length() {
      let end = Int::min(payload.length(), offset + 16384)
      match
        @publication.feed_durable_result_row_frames(
          frames,
          payload[offset:end].to_owned(),
        ) {
        Ok(next) =>
          for row in next {
            rows.push(row)
          }
        Err(@publication.DurableRowFrameRowSizeLimit) => {
          refused = true
          break
        }
        Err(_) =>
          fail(
            "the original durable row framer must preserve its typed refusal",
          )
      }
      offset = end
    }
    if admitted {
      assert_false(refused)
      assert_eq(rows, [row])
      assert_eq(
        @publication.finish_durable_result_row_frames(frames),
        Ok({ bytes: payload.length(), rows: 1, }),
      )
    } else {
      assert_true(refused)
      assert_eq(rows, [])
    }
  }
}
