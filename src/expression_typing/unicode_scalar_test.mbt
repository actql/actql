///|
test "Unicode scalar result types preserve nullability and CHR bounded String" {
  let fields = "{\"s\":{\"type\":\"string\",\"nullable\":false},\"t\":{\"type\":\"string\",\"nullable\":true},\"n\":{\"type\":\"number\",\"nullable\":false},\"m\":{\"type\":\"number\",\"nullable\":true}}"
  for tag in ["byte_length", "octet_length", "unicode"] {
    for
      (arg, nullable) in [
        ("s", "false"),
        ("t", "true"),
        ("NULL", "true"),
        ("''", "false"),
      ] {
      assert_type(
        "\"" + tag + "(" + arg + ")\"",
        fields,
        "null",
        "{\"type\":\"number\",\"nullable\":" + nullable + "}",
      )
    }
    for arg in ["1", "TRUE", "[1]", "n"] {
      assert_rejected(
        "\"" + tag + "(" + arg + ")\"",
        fields,
        "null",
        "TypeMismatch",
      )
    }
  }
  for
    (arg, nullable) in [
      ("n", "false"),
      ("m", "true"),
      ("NULL", "true"),
      ("0", "false"),
      ("-1", "false"),
      ("0.5", "false"),
    ] {
    assert_type(
      "\"chr(" + arg + ")\"",
      fields,
      "null",
      "{\"type\":\"string\",\"nullable\":" +
      nullable +
      ",\"max_codepoints\":1,\"max_utf8_bytes\":4}",
    )
  }
  for arg in ["s", "'65'", "TRUE", "[65]"] {
    assert_rejected("\"chr(" + arg + ")\"", fields, "null", "TypeMismatch")
  }
}
