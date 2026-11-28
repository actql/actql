///|
test "utf8 range copies exact bytes across non-ASCII scalar edges" {
  let body = "Aé日😀Z"
  let encoded = b"A\xC3\xA9\xE6\x97\xA5\xF0\x9F\x98\x80Z"
  for start in 0..<encoded.length() {
    for end in (start + 1)..<=encoded.length() {
      assert_eq(
        copy_utf8_byte_range(body, start, end - start),
        Some(
          Bytes::from_array(
            Array::makei(end - start, index => encoded[start + index]),
          ),
        ),
      )
    }
  }
  assert_true(copy_utf8_byte_range(body, -1, 1) is None)
  assert_true(copy_utf8_byte_range(body, encoded.length() - 1, 2) is None)
  assert_true(copy_utf8_byte_range(body, 2147483647, 1) is None)
}
