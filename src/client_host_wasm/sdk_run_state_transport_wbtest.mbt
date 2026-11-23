///|
test "SDK RunState transport measures the original escaped Unicode packet" {
  let key = "original"
  let body = @utf8.encode(
    (
      #|{"intent":"a\"b","text":"é🌱"}
    ),
  )
  let state =
    #|{"run_id":"é🌱","revision":2}
  let expected =
    #|{"body":"{\"intent\":\"a\\\"b\",\"text\":\"é🌱\"}","key":"original","kind":"replace","revision":"15","state":"{\"run_id\":\"é🌱\",\"revision\":2}"}
  let expected_bytes = @utf8.encode(expected).length()
  let measure = @encode.measuring_writer(1048576, 16, 1)
  write_sdk_run_state_fields(measure, key, 15L, 16L, body, state)
  assert_eq(@encode.finish_measurement(measure), expected_bytes)
  let exact = @encode.writer(expected_bytes, 16, 1)
  write_sdk_run_state_fields(exact, key, 15L, 16L, body, state)
  assert_eq(@encode.finish(exact), expected)
  let short = @encode.writer(expected_bytes - 1, 16, 1)
  let refused = try {
    write_sdk_run_state_fields(short, key, 15L, 16L, body, state)
    @encode.finish(short) |> ignore
    false
  } catch {
    @encode.OutputLimit => true
    _ => false
  }
  assert_true(refused)
}
