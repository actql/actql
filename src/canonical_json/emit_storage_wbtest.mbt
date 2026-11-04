///|
test "canonical emission retires popped payloads and retains actual backing geometry" {
  let mut deep : CanonicalValue = Null
  for _ in 0..<40 {
    deep = Array({ values: [deep], })
  }
  let value = Array({ values: [deep, Bool(true)], })
  let output = @encode.buffered_writer(10000, 100, 50, 10000)
  let cursor = start_emit(value, output)
  let fragments = []
  let mut deep_seen = false
  let mut shallow_seen = false
  for _ in 0..<500 {
    let before = cursor.pending.length()
    let done = advance_emit(cursor)
    if before > 30 {
      deep_seen = true
    }
    if deep_seen && cursor.pending.length() <= 2 {
      shallow_seen = true
    }
    if cursor.pending.length() < before && cursor.pending.capacity() >= before {
      assert_true(cursor.pending.unsafe_get(before - 1) is EmitRetired)
    }
    assert_true(emit_storage_frames(cursor) >= emit_pending_frames(cursor))
    fragments.push(@encode.drain_buffered_output(output))
    if done {
      break
    }
  }
  assert_true(deep_seen && shallow_seen)
  @encode.finish_buffered_usage(output) |> ignore
  assert_eq(
    fragments.join(""),
    "[" + "[".repeat(40) + "null" + "]".repeat(40) + ",true]",
  )
  cancel_emit(cursor)
  assert_eq(emit_pending_frames(cursor), 0)
}
