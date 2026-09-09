///|
fn limits(
  bytes? : Int = 1000000,
  nodes? : Int = 100000,
  depth? : Int = 20000,
) -> JsonLimits {
  { max_input_bytes: bytes, max_nodes: nodes, max_depth: depth, }
}

///|
fn parsed(text : String) -> Node {
  parse_json(text, limits()).unwrap()
}

///|
fn rejected(text : String) -> ParseError raise {
  match parse_json(text, limits()) {
    Err(error) => error
    Ok(_) => fail("expected JSON rejection")
  }
}

///|
test "JSON roots and editable ordered fields preserve structure" {
  assert_true(parsed("null").value is Null)
  assert_true(parsed(" true ").value is Bool(true))
  assert_true(parsed("false").value is Bool(false))
  assert_true(parsed("12.5").value is Number(12.5))
  assert_true(parsed("\"hello\"").value is String("hello"))
  assert_true(parsed("[]").value is Array([]))
  assert_true(parsed("{}").value is Object([]))
  guard parsed("{\"b\":[true,null,{\"n\":-2}],\"a\":[]}").value
    is Object(fields) else {
    fail("expected object")
  }
  assert_eq(fields.map(field => field.key), ["b", "a"])
  guard fields[0].value.value is Array(items) else { fail("expected array") }
  assert_eq(items.length(), 3)
  assert_true(items[0].value is Bool(true))
  assert_true(items[1].value is Null)
  guard items[2].value is Object(nested) else { fail("expected nested object") }
  assert_true(nested[0].value.value is Number(-2.0))
}

///|
test "source strings normalize NFC then LF but not compatibility or other separators" {
  for
    (source, expected) in [
      ("\"e\\u0301\"", "é"),
      ("\"\\u0344\"", "\u0308\u0301"),
      ("\"\\r\\nX\\rY\\n\"", "\nX\nY\n"),
      ("\"\\uD83D\\uDE00\"", "😀"),
      ("\"😀\"", "😀"),
      ("\"\\u0000\\b\\f\\t\\\"\\\\\\/\"", "\u0000\b\f\t\"\\/"),
      ("\"ﬁ\\u0085\\u2028\\u2029\\ufeff\"", "ﬁ\u0085\u2028\u2029\ufeff"),
      ("\"\\u0378\"", "\u0378"),
    ] {
    guard parsed(source).value is String(text) else { fail("expected string") }
    assert_eq(text, expected)
  }
  guard parsed("{\"e\\u0301\":1,\"x\\r\\n\":2}").value is Object(fields) else {
    fail("expected object")
  }
  assert_eq(fields.map(field => field.key), ["é", "x\n"])
}

///|
test "keys collide after escape decoding and NFC LF before their values are parsed" {
  for
    (source, key) in [
      ("{\"a\":1,\"a\":???}", "a"),
      ("{\"a\":1,\"\\u0061\":2}", "a"),
      ("{\"é\":1,\"e\\u0301\":2}", "é"),
      ("{\"x\\r\\n\":1,\"x\\n\":2}", "x\n"),
    ] {
    let error = rejected(source)
    assert_eq(error.issue, DuplicateKey(key))
    assert_eq(error.path, Some([Key(key)]))
  }
  // An earlier invalid value wins over a later duplicate.
  assert_eq(rejected("{\"a\":?,\"a\":1}").issue, UnexpectedToken)
  guard parsed("{\"ﬁ\":1,\"fi\":2,\"A\":3,\"a\":4}").value is Object(fields) else {
    fail("expected distinct keys")
  }
  assert_eq(fields.length(), 4)
}

///|
test "JSON grammar rejects malformed tokens separators strings and trailing documents" {
  for
    text in [
      "", " ", "undefined", "NaN", "Infinity", "yes", "nul", "True", "+1", ".1",
      "01", "-01", "1.", "1e", "1e+", "1_0", "0x1", "--1", "[", "[1", "[1,]", "[,1]",
      "[1 2]", "{", "{a:1}", "{'a':1}", "{\"a\" 1}", "{\"a\":}", "{\"a\":1,}", "{\"a\":1 \"b\":2}",
      "null null", "{}[]", "1true", "//comment\n1", "/*comment*/1", "\"unterminated",
      "\"raw\nline\"", "\"raw\tcontrol\"", "\"\\x20\"", "\"\\u12g4\"", "\"\\u123\"",
      "\"\\v\"", "\"\\'\"",
    ] {
    assert_true(parse_json(text, limits()) is Err(_))
  }
  for text in ["null null", "{}[]", "1true"] {
    assert_eq(rejected(text).issue, TrailingContent)
  }
}

///|
test "escaped isolated surrogates are rejected rather than replaced" {
  for
    text in [
      "\"\\ud800\"", "\"\\udc00\"", "\"\\ud800A\"", "\"\\ud800\\u0041\"", "\"\\ud800\\ud800\"",
      "{\"\\udfff\":0}",
    ] {
    assert_eq(rejected(text).issue, InvalidUnicodeEscape)
  }
}
