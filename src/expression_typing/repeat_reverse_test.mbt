///|
test "repeat drops expanding String bounds and reverse preserves exact String contract" {
  let fields = "{\"s\":{\"type\":\"string\",\"nullable\":false,\"min_length\":2,\"max_codepoints\":8,\"max_utf8_bytes\":32},\"t\":{\"type\":\"string\",\"nullable\":true,\"min_length\":1,\"max_codepoints\":3,\"max_utf8_bytes\":12},\"n\":{\"type\":\"number\",\"nullable\":false},\"m\":{\"type\":\"number\",\"nullable\":true}}"
  repeat_reverse_assert_type(
    "\"reverse(s)\"", fields, "null", "{\"type\":\"string\",\"nullable\":false,\"min_length\":2,\"max_codepoints\":8,\"max_utf8_bytes\":32}",
  )
  repeat_reverse_assert_type(
    "\"reverse(t)\"", fields, "null", "{\"type\":\"string\",\"nullable\":true,\"min_length\":1,\"max_codepoints\":3,\"max_utf8_bytes\":12}",
  )
  repeat_reverse_assert_type(
    "\"reverse(NULL)\"", fields, "null", "{\"type\":\"string\",\"nullable\":true}",
  )
  for
    (args, nullable) in [
      ("s,n", "false"),
      ("s,m", "true"),
      ("t,n", "true"),
      ("NULL,0", "true"),
      ("s,NULL", "true"),
      ("NULL,NULL", "true"),
      ("s,-1", "false"),
      ("s,0.5", "false"),
      ("s,1e100", "false"),
    ] {
    repeat_reverse_assert_type(
      "\"repeat(" + args + ")\"",
      fields,
      "null",
      "{\"type\":\"string\",\"nullable\":" + nullable + "}",
    )
  }
  let fields = "{\"s\":{\"type\":\"string\",\"nullable\":false},\"n\":{\"type\":\"number\",\"nullable\":false}}"
  for args in ["1,2", "TRUE,2", "[1],2", "s,'2'", "s,TRUE", "s,[2]"] {
    assert_rejected("\"repeat(" + args + ")\"", fields, "null", "TypeMismatch")
  }
  for arg in ["1", "TRUE", "[1]", "n"] {
    assert_rejected("\"reverse(" + arg + ")\"", fields, "null", "TypeMismatch")
  }
}

///|
fn repeat_reverse_assert_type(
  source : String,
  fields : String,
  parameters : String,
  expected : String,
) -> Unit raise {
  // Bounds are checked evidence, not author-declared parameter syntax.
  let scope = @contract.read_checked(
    cursor(
      "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":" +
      fields +
      "}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let actual = @expression_typing.check(
    syntax(source),
    { ..env(parameters~), fields: Some(scope), },
    test_limits(),
  ).unwrap()
  let expected = @contract.read_checked(cursor(expected), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
  assert_eq(
    @contract.stringify_checked(
      @expression_typing.result_type(actual),
      1000000,
      100000,
      30000,
    ),
    @contract.stringify_checked(expected, 1000000, 100000, 30000),
    msg=source,
  )
}
