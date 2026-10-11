///|
fn assert_split_type(
  source : String,
  fields : String,
  parameters : String,
  expected : String,
) -> Unit raise {
  let scope = @contract.read_checked(
    cursor(
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":" +
      fields +
      "}",
    ),
    { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  ).unwrap()
  let result = @expression_typing.check(
    syntax(source),
    { ..env(parameters~), fields: Some(scope), },
    test_limits(),
  ).unwrap()
  let expected = @contract.read_checked(cursor(expected), {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  assert_true(
    @contract.type_equal(@expression_typing.result_type(result), expected, 1000),
    msg=source,
  )
}

///|
test "split returns nullable Array of nonnullable bounded String parts" {
  let fields = "{\"s\":{\"type\":\"string\",\"nullable\":false,\"min_length\":2,\"max_codepoints\":8,\"max_utf8_bytes\":32},\"d\":{\"type\":\"string\",\"nullable\":true}}"
  for (args, nullable) in [("s", "false"), ("s,d", "true"), ("s,NULL", "true")] {
    assert_split_type(
      "\"split(" + args + ")\"",
      fields,
      "null",
      "{\"type\":\"array\",\"nullable\":" +
      nullable +
      ",\"max_items\":9,\"items\":{\"type\":\"string\",\"nullable\":false,\"max_codepoints\":8,\"max_utf8_bytes\":32}}",
    )
  }
  for args in ["NULL", "NULL,NULL", "NULL,','"] {
    assert_split_type(
      "\"split(" + args + ")\"",
      "{}",
      "null",
      "{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"string\",\"nullable\":false}}",
    )
  }
  assert_split_type(
    "\"split('', '')\"", "{}", "null", "{\"type\":\"array\",\"nullable\":false,\"max_items\":1,\"items\":{\"type\":\"string\",\"nullable\":false,\"max_utf8_bytes\":0}}",
  )
  assert_split_type(
    "\"split(lower('ABC'), upper(','))\"", "{}", "null", "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"string\",\"nullable\":false}}",
  )
  assert_split_type(
    "\"split(s, $p)\"", fields, "{\"p\":{\"type\":\"string\"}}", "{\"type\":\"array\",\"nullable\":false,\"max_items\":9,\"items\":{\"type\":\"string\",\"nullable\":false,\"max_codepoints\":8,\"max_utf8_bytes\":32}}",
  )
  for args in ["1", "TRUE", "'a',1", "'a',[1]", "split('a')"] {
    assert_rejected("\"split(" + args + ")\"", "{}", "null", "TypeMismatch")
  }
}

///|
test "split does not overflow max items or inherit false minimum bounds" {
  for
    (bounds, expected) in [
      (
        "\"max_utf8_bytes\":7", "\"max_items\":8,\"items\":{\"type\":\"string\",\"nullable\":false,\"max_utf8_bytes\":7}",
      ),
      (
        "\"max_codepoints\":9007199254740991", "\"items\":{\"type\":\"string\",\"nullable\":false,\"max_codepoints\":9007199254740991}",
      ),
      (
        "\"max_codepoints\":9,\"max_utf8_bytes\":3", "\"max_items\":4,\"items\":{\"type\":\"string\",\"nullable\":false,\"max_codepoints\":9,\"max_utf8_bytes\":3}",
      ),
    ] {
    assert_split_type(
      "\"split(s)\"",
      "{\"s\":{\"type\":\"string\",\"nullable\":false," + bounds + "}}",
      "null",
      "{\"type\":\"array\",\"nullable\":false," + expected + "}",
    )
  }
}
