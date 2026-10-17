///|
test "Text transformations preserve original input enumeration and derive sound outputs" {
  let fields = "{\"s\":{\"type\":\"string\",\"nullable\":false,\"enum\":[\"ab\"],\"min_length\":2,\"max_codepoints\":2,\"max_utf8_bytes\":2}}"
  repeat_reverse_assert_type(
    "\"s\"", fields, "null", "{\"type\":\"string\",\"nullable\":false,\"enum\":[\"ab\"],\"min_length\":2,\"max_codepoints\":2,\"max_utf8_bytes\":2}",
  )
  repeat_reverse_assert_type(
    "\"lower(s)\"", fields, "null", "{\"type\":\"string\",\"nullable\":false}",
  )
  // Reversal preserves length bounds, but "ba" is not the original "ab".
  repeat_reverse_assert_type(
    "\"reverse(s)\"", fields, "null", "{\"type\":\"string\",\"nullable\":false,\"min_length\":2,\"max_codepoints\":2,\"max_utf8_bytes\":2}",
  )
}
