///|
test "SDK RunState transport carries the original row and Unicode state exactly" {
  let key = "sha256:" + "a".repeat(64)
  let body = @utf8.encode(
    (
      #|{"intent":"a\"b","text":"é🌱"}
    ),
  )
  let state =
    #|{"run_id":"é🌱","revision":2}
  let state_bytes = @utf8.encode(state)
  let bytes = 84 + body.length() + state_bytes.length()
  assert_eq(sdk_run_state_transport_extent(key, body, state), Some(bytes))
  let prefix = b"\x0f\x00\x00\x00\x00\x00\x00\x00"
  let extent = Bytes::makei(4, index => (body.length() >> (index * 8)).to_byte())
  let fields = @utf8.encode(key) + body + state_bytes
  assert_eq(
    sdk_run_state_transport_packet(key, 15L, 16L, body, state, bytes),
    Some(prefix + extent + b"\x01" + fields),
  )
  assert_eq(
    sdk_run_state_transport_packet(key, 15L, 15L, body, state, bytes),
    Some(prefix + extent + b"\x00" + fields),
  )
}

///|
test "SDK RunState transport refuses foreign extents and revisions" {
  let key = "sha256:" + "a".repeat(64)
  let body = b"{}"
  let state = "{}"
  let bytes = 88
  assert_eq(sdk_run_state_transport_packet(key, 15L, 16L, body, state, bytes - 1), None)
  assert_eq(sdk_run_state_transport_packet(key, 15L, 17L, body, state, bytes), None)
  assert_eq(sdk_run_state_transport_extent(key, body, ""), None)
}
