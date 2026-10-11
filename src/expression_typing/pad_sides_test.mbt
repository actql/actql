///|
test "side slices preserve sound input maxima and padding drops expanding ceilings" {
  let fields = "{\"s\":{\"type\":\"string\",\"nullable\":false,\"min_length\":2,\"max_codepoints\":8,\"max_utf8_bytes\":32},\"n\":{\"type\":\"number\",\"nullable\":true},\"p\":{\"type\":\"string\",\"nullable\":true}}"
  let scope = @contract.read_checked(
    cursor(
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":" +
      fields +
      "}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for name in ["left", "right", "lpad", "rpad"] {
    for (arg, nullable) in [("100", false), ("n", true)] {
      let typed = @expression_typing.check(
        syntax("\"" + name + "(s," + arg + ")\""),
        { ..env(), fields: Some(scope), },
        test_limits(),
      ).unwrap()
      let actual = @expression_typing.result_type(typed)
      assert_eq(actual.nullable, nullable)
      guard actual.shape is @contract.Text(bounds) else {
        fail("String contract")
      }
      assert_eq(bounds.min_length, None)
      if name == "left" || name == "right" {
        assert_eq(
          (bounds.max_codepoints, bounds.max_utf8_bytes),
          (Some(8L), Some(32L)),
        )
      } else {
        assert_eq((bounds.max_codepoints, bounds.max_utf8_bytes), (None, None))
      }
    }
  }
  let fields = "{\"s\":{\"type\":\"string\",\"nullable\":false},\"n\":{\"type\":\"number\",\"nullable\":true},\"p\":{\"type\":\"string\",\"nullable\":true}}"
  for name in ["lpad", "rpad"] {
    assert_type(
      "\"" + name + "(s, 100)\"",
      fields,
      "null",
      "{\"type\":\"string\",\"nullable\":false}",
    )
    assert_type(
      "\"" + name + "(s, 100, p)\"",
      fields,
      "null",
      "{\"type\":\"string\",\"nullable\":true}",
    )
    assert_type(
      "\"" + name + "(s, n, 'x')\"",
      fields,
      "null",
      "{\"type\":\"string\",\"nullable\":true}",
    )
    assert_type(
      "\"" + name + "(s, -1, '')\"",
      fields,
      "null",
      "{\"type\":\"string\",\"nullable\":false}",
    )
    assert_rejected("\"" + name + "(s, 2, 1)\"", fields, "null", "TypeMismatch")
  }
  for name in ["left", "right", "lpad", "rpad"] {
    assert_type(
      "\"" + name + "(NULL, NULL)\"",
      "{}",
      "null",
      "{\"type\":\"string\",\"nullable\":true}",
    )
    assert_rejected("\"" + name + "(1, 2)\"", "{}", "null", "TypeMismatch")
    assert_rejected("\"" + name + "('s', '2')\"", "{}", "null", "TypeMismatch")
    assert_rejected("\"" + name + "('s', TRUE)\"", "{}", "null", "TypeMismatch")
  }
}
