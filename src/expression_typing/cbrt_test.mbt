///|
test "cbrt Number signature preserves operand nullability and rejects coercions" {
  let fields = "{\"n\":{\"type\":\"number\",\"nullable\":false},\"m\":{\"type\":\"number\",\"nullable\":true},\"s\":{\"type\":\"string\",\"nullable\":false},\"d\":{\"type\":\"decimal\",\"nullable\":false,\"precision\":8,\"scale\":3}}"
  for
    (arg, nullable) in [
      ("n", "false"),
      ("m", "true"),
      ("NULL", "true"),
      ("-27", "false"),
      ("0.5", "false"),
    ] {
    assert_type(
      "\"cbrt(" + arg + ")\"",
      fields,
      "null",
      "{\"type\":\"number\",\"nullable\":" + nullable + "}",
    )
  }
  for arg in ["s", "d", "'8'", "TRUE", "[8]"] {
    assert_rejected("\"cbrt(" + arg + ")\"", fields, "null", "TypeMismatch")
    assert_rejected(
      "\"if(FALSE,cbrt(" + arg + "),1)\"",
      fields,
      "null",
      "TypeMismatch",
    )
  }
  assert_type(
    "\"if(FALSE,cbrt(1 / 0),7)\"", fields, "null", "{\"type\":\"number\",\"nullable\":false}",
  )
}
