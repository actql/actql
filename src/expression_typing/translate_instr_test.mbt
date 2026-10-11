///|
test "translate instr nullable types check every ordered argument and retain only safe codepoint bounds" {
  let fields = "{\"s\":{\"type\":\"string\",\"nullable\":false,\"min_length\":2,\"max_codepoints\":8,\"max_utf8_bytes\":32},\"t\":{\"type\":\"string\",\"nullable\":true},\"n\":{\"type\":\"number\",\"nullable\":false},\"m\":{\"type\":\"number\",\"nullable\":true}}"
  translate_instr_assert_type(
    "\"translate(s,s,s)\"", fields, "null", "{\"type\":\"string\",\"nullable\":false,\"max_codepoints\":8}",
  )
  translate_instr_assert_type(
    "\"translate(t,s,s)\"", fields, "null", "{\"type\":\"string\",\"nullable\":true}",
  )
  translate_instr_assert_type(
    "\"translate(s,t,s)\"", fields, "null", "{\"type\":\"string\",\"nullable\":true,\"max_codepoints\":8}",
  )
  translate_instr_assert_type(
    "\"translate(s,s,t)\"", fields, "null", "{\"type\":\"string\",\"nullable\":true,\"max_codepoints\":8}",
  )
  translate_instr_assert_type(
    "\"translate(NULL,s,s)\"", fields, "null", "{\"type\":\"string\",\"nullable\":true}",
  )
  translate_instr_assert_type(
    "\"translate(s,NULL,s)\"", fields, "null", "{\"type\":\"string\",\"nullable\":true,\"max_codepoints\":8}",
  )
  translate_instr_assert_type(
    "\"translate(s,s,NULL)\"", fields, "null", "{\"type\":\"string\",\"nullable\":true,\"max_codepoints\":8}",
  )
  translate_instr_assert_type(
    "\"instr(s,s)\"", fields, "null", "{\"type\":\"number\",\"nullable\":false}",
  )
  translate_instr_assert_type(
    "\"instr(t,s)\"", fields, "null", "{\"type\":\"number\",\"nullable\":true}",
  )
  translate_instr_assert_type(
    "\"instr(s,t)\"", fields, "null", "{\"type\":\"number\",\"nullable\":true}",
  )
  translate_instr_assert_type(
    "\"instr(s,s,n)\"", fields, "null", "{\"type\":\"number\",\"nullable\":false}",
  )
  translate_instr_assert_type(
    "\"instr(s,s,m)\"", fields, "null", "{\"type\":\"number\",\"nullable\":true}",
  )
  translate_instr_assert_type(
    "\"instr(s,s,n,m)\"", fields, "null", "{\"type\":\"number\",\"nullable\":true}",
  )
  translate_instr_assert_type(
    "\"instr(s,s,m,n)\"", fields, "null", "{\"type\":\"number\",\"nullable\":true}",
  )
  translate_instr_assert_type(
    "\"instr(s,s,NULL,NULL)\"", fields, "null", "{\"type\":\"number\",\"nullable\":true}",
  )
  translate_instr_assert_type(
    "\"instr(s,s,0,-1)\"", fields, "null", "{\"type\":\"number\",\"nullable\":false}",
  )
  translate_instr_assert_type(
    "\"instr(s,s,0.5,1e100)\"", fields, "null", "{\"type\":\"number\",\"nullable\":false}",
  )
  let fields = "{\"s\":{\"type\":\"string\",\"nullable\":false},\"t\":{\"type\":\"string\",\"nullable\":true},\"n\":{\"type\":\"number\",\"nullable\":false},\"m\":{\"type\":\"number\",\"nullable\":true}}"
  assert_rejected("\"translate(1,s,s)\"", fields, "null", "TypeMismatch")
  assert_rejected("\"translate(s,TRUE,s)\"", fields, "null", "TypeMismatch")
  assert_rejected("\"translate(s,s,[1])\"", fields, "null", "TypeMismatch")
  assert_rejected("\"instr(1,s)\"", fields, "null", "TypeMismatch")
  assert_rejected("\"instr(s,TRUE)\"", fields, "null", "TypeMismatch")
  assert_rejected("\"instr(s,s,'1')\"", fields, "null", "TypeMismatch")
  assert_rejected("\"instr(s,s,1,FALSE)\"", fields, "null", "TypeMismatch")
  assert_rejected("\"instr(NULL,1)\"", fields, "null", "TypeMismatch")
  assert_rejected("\"instr(NULL,s,TRUE)\"", fields, "null", "TypeMismatch")
}

///|
fn translate_instr_assert_type(
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
