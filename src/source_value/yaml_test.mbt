///|
test "YAML quoted merge spellings are ordinary string keys" {
  for key in ["\"<<\"", "'<<'", "\"\\u003c\\u003c\""] {
    for
      source in [
        "meta: {" + key + ": \"ordinary data\"}",
        "meta:\n  " + key + ": \"ordinary data\"",
      ] {
      same_values(yaml(source), parsed("{\"meta\":{\"<<\":\"ordinary data\"}}"))
      same_values(
        yaml(source),
        parse_yaml_bytes(@utf8.encode(source), limits()).unwrap(),
        spans=true,
      )
    }
    let source = key + ": 1"
    guard yaml(source).value is Object(fields) else { fail("expected object") }
    assert_eq(fields[0].key, "<<")
    assert_eq(
      (fields[0].key_span.start_byte, fields[0].key_span.end_byte),
      (0, key.length()),
    )
  }
  for source in ["{\"<<\": 0, '<<': 1}", "\"<<\": 0\n\"\\u003c\\u003c\": 1"] {
    assert_eq(yaml_error(source).issue, DuplicateKey("<<"))
  }
  for
    source in ["<<: {}", "{<<: {}}", "a: &id value", "a: *id", "a: !!str value"] {
    assert_eq(yaml_error(source).issue, ForbiddenYamlFeature)
  }
}

///|
test "YAML flow separation tabs follow space indentation" {
  for
    (source, spaces, expected) in [
      (
        "items: [\n  \t1,\n  2\n]", "items: [\n   1,\n  2\n]", "{\"items\":[1,2]}",
      ),
      ("{\n  \t\"x\": 1\n}", "{\n   \"x\": 1\n}", "{\"x\":1}"),
      (
        "items: [\r\n  \t1,\r\n  2\r\n]", "items: [\r\n   1,\r\n  2\r\n]", "{\"items\":[1,2]}",
      ),
      (
        "a:\n  items: [\n   \t1,\n   \t2\n  ]", "a:\n  items: [\n    1,\n    2\n  ]",
        "{\"a\":{\"items\":[1,2]}}",
      ),
      (
        "items: [{\n \t\"x\":\n \t1\n}]", "items: [{\n  \"x\":\n  1\n}]", "{\"items\":[{\"x\":1}]}",
      ),
      (
        "items: [\n \t? \"x\"\n \t: 1\n]", "items: [\n  ? \"x\"\n  : 1\n]", "{\"items\":[{\"x\":1}]}",
      ),
    ] {
    let actual = yaml(source)
    same_values(actual, parsed(expected))
    same_values(actual, yaml(spaces))
    same_values(
      actual,
      parse_yaml_bytes(@utf8.encode(source), limits()).unwrap(),
      spans=true,
    )
  }
  guard yaml("items: [\n  \t1,\n  2\n]").value is Object(fields) else {
    fail("expected object")
  }
  guard fields[0].value.value is Array(items) else { fail("expected array") }
  assert_eq((items[0].span.start_byte, items[0].span.end_byte), (12, 13))
  assert_eq((items[0].span.start_line, items[0].span.start_column), (2, 4))
}

///|
test "YAML separation tabs cannot replace required indentation" {
  for
    source in [
      "a:\n\tb: 1", "a:\n \tb: 1", "items: [\n\t1\n]", "items: [\n\t 1\n]", "a:\n  items: [\n  \t1\n  ]",
      "items: [1]\n\tnext: 2",
    ] {
    assert_eq(yaml_error(source).issue, InvalidYamlIndentation)
  }
  same_values(yaml("a: |\n  \tvalue\n"), parsed("{\"a\":\"\\tvalue\\n\"}"))
}

///|
test "YAML folding preserves escaped whitespace but trims raw separation" {
  for
    (source, expected) in [
      ("\"a\\t\n  b\"", "\"a\\t b\""),
      ("\"a\\ \n  b\"", "\"a  b\""),
      ("\"a\\u0020  \t\r\n  b\"", "\"a  b\""),
      ("\"a \t\n  b\"", "\"a b\""),
      ("\"a\\t\n\n  b\"", "\"a\\t\\nb\""),
      ("'a \t\n  b'", "\"a b\""),
    ] {
    same_values(yaml(source), parsed(expected))
  }
}

///|
test "YAML blank-only block scalars infer indentation" {
  for
    (source, expected) in [
      ("|+\n  \n", "\"\\n\""),
      (">+\n  \n    \n", "\"\\n\\n\""),
      ("|\n  \n", "\"\""),
      ("|-\n  \n", "\"\""),
      ("a: |+\r\n  \r\n", "{\"a\":\"\\n\"}"),
    ] {
    same_values(yaml(source), parsed(expected))
  }
  ignore(yaml_error("|\n    \n  text\n"))
}

///|
test "YAML adjacent quoted mapping values require flow style" {
  for
    source in [
      "\"a\":1", "'a':true", "- \"a\":1", "first: 0\n\"a\":1", "? \"a\"\n:1",
    ] {
    ignore(yaml_error(source))
  }
  for source in ["{\"a\":1}", "{'a':1}", "\"a\": 1"] {
    same_values(yaml(source), parsed("{\"a\":1}"))
  }
}

///|
test "YAML quoted continuation requires spaces before separation tabs" {
  for
    source in [
      "a: \"x\n\t y\"", "a: 'x\n\t y'", "a: \"x\\\n\t y\"", "a:\n  b: \"x\n  \t y\"",
    ] {
    assert_eq(yaml_error(source).issue, InvalidYamlIndentation)
  }
  same_values(yaml("a: \"x\n \t y\""), parsed("{\"a\":\"x y\"}"))
  same_values(yaml("a: \"x\\\n \t y\""), parsed("{\"a\":\"xy\"}"))
}

///|
fn yaml(source : String) -> Node raise {
  match parse_yaml(source, limits()) {
    Ok(value) => value
    Err(error) => {
      debug_inspect(error, content="no parse error")
      fail("unexpected YAML rejection")
    }
  }
}

///|
fn yaml_error(source : String) -> ParseError raise {
  match parse_yaml(source, limits()) {
    Err(error) => error
    Ok(_) => fail("expected YAML rejection")
  }
}

///|
fn same_values(
  actual : Node,
  expected : Node,
  spans? : Bool = false,
) -> Unit raise {
  let pending = [(actual, expected)]
  while pending.length() > 0 {
    let (a, b) = pending.pop().unwrap()
    if spans {
      assert_eq(a.span, b.span)
    }
    match (a.value, b.value) {
      (Null, Null) => ()
      (Bool(a), Bool(b)) => assert_eq(a, b)
      (Number(a), Number(b)) =>
        assert_eq(a.reinterpret_as_uint64(), b.reinterpret_as_uint64())
      (String(a), String(b)) => assert_eq(a, b)
      (Array(a), Array(b)) => {
        assert_eq(a.length(), b.length())
        for i = 0; i < a.length(); i = i + 1 {
          pending.push((a[i], b[i]))
        }
      }
      (Object(a), Object(b)) => {
        assert_eq(a.length(), b.length())
        for i = 0; i < a.length(); i = i + 1 {
          assert_eq(a[i].key, b[i].key)
          if spans {
            assert_eq(a[i].key_span, b[i].key_span)
          }
          pending.push((a[i].value, b[i].value))
        }
      }
      _ => fail("different value kinds")
    }
  }
}

///|
test "YAML block flow compact and indentationless collections" {
  for
    (source, expected) in [
      ("a: 1\nb: true\n", "{\"a\":1,\"b\":true}"),
      ("- one\n- two\n", "[\"one\",\"two\"]"),
      (
        "stages:\n- id: a\n  active: true\n- id: b\nnext: true\n", "{\"stages\":[{\"id\":\"a\",\"active\":true},{\"id\":\"b\"}],\"next\":true}",
      ),
      ("- - one\n  - two\n- - three", "[[\"one\",\"two\"],[\"three\"]]"),
      ("{\"a\":1, 'b': [true,],}", "{\"a\":1,\"b\":[true]}"),
      ("[a: 1, b: 2]", "[{\"a\":1},{\"b\":2}]"),
      ("{a, b:}", "{\"a\":null,\"b\":null}"),
      ("first:\nsecond: 2", "{\"first\":null,\"second\":2}"),
      ("-\n- value", "[null,\"value\"]"),
      ("? name\n: value", "{\"name\":\"value\"}"),
      ("? first\n  last\n: value", "{\"first last\":\"value\"}"),
      ("{? name: value}", "{\"name\":\"value\"}"),
      (
        "{\n a: [1,\n 2, # comment\n 3],\n b: true\n}", "{\"a\":[1,2,3],\"b\":true}",
      ),
      (
        "a: http://host/x\nb: hello#world\nc: hello # comment", "{\"a\":\"http://host/x\",\"b\":\"hello#world\",\"c\":\"hello\"}",
      ),
    ] {
    same_values(yaml(source), parsed(expected))
  }
}

///|
test "YAML bytes and text share spans across line endings and scalar styles" {
  for separator in ["\n", "\r\n", "\r"] {
    let source = "\ufeffa:\"x\""
    // This plain scalar has no mapping separator; the quoted characters are data.
    let bytes = @utf8.encode(source)
    same_values(
      yaml(source),
      parse_yaml_bytes(bytes, limits()).unwrap(),
      spans=true,
    )
    let source = [
      "\ufeffé:", "  - '😀'", "  - |", "    e\u0301", "    text", "z: false",
    ].join(separator)
    let bytes = @utf8.encode(source)
    same_values(
      yaml(source),
      parse_yaml_bytes(bytes, limits()).unwrap(),
      spans=true,
    )
    assert_true(parse_yaml_bytes(bytes, limits(bytes=bytes.length())) is Ok(_))
    guard parse_yaml_bytes(bytes, limits(bytes=bytes.length() - 1))
      is Err(error) else {
      fail("expected input limit")
    }
    assert_eq(error.issue, InputLimit)
  }
}

///|
test "YAML indented blocks and wide mappings respect budgets and preserve ownership" {
  let depth = 600
  let input = StringBuilder()
  for i = 0; i < depth; i = i + 1 {
    input.write_string(" ".repeat(i))
    input.write_string("a:\n")
  }
  input.write_string(" ".repeat(depth))
  input.write_string("true")
  let source = input.to_string()
  let mut root = parse_yaml(source, limits(nodes=depth + 1, depth~)).unwrap()
  for i = 0; i < depth; i = i + 1 {
    guard root.value is Object(fields) else { fail("expected object") }
    root = fields[0].value
  }
  assert_true(root.value is Bool(true))
  guard parse_yaml(source, limits(depth=depth - 1)) is Err(error) else {
    fail("expected depth limit")
  }
  assert_eq(error.issue, DepthLimit)
  let wide = StringBuilder()
  for i = 0; i < 10000; i = i + 1 {
    wide.write_string("field" + i.to_string() + ": true\n")
  }
  assert_true(parse_yaml(wide.to_string(), limits(nodes=10001)) is Ok(_))
  guard parse_yaml(wide.to_string(), limits(nodes=10000)) is Err(error) else {
    fail("expected node limit")
  }
  assert_eq(error.issue, NodeLimit)
  let first = yaml("a: [1]\nb: [2]")
  let second = yaml("a: [1]\nb: [2]")
  guard first.value is Object(fields) else { fail("expected object") }
  guard fields[0].value.value is Array(items) else { fail("expected array") }
  items[0] = parsed("99")
  assert_true(fields[1].value.value is Array([{ value: Number(2.0), .. }]))
  same_values(second, parsed("{\"a\":[1],\"b\":[2]}"))
}

///|
test "YAML Core scalar resolution is not JSON spelling or YAML 1.1 resolution" {
  for
    (source, expected) in [
      ("null", "null"),
      ("~", "null"),
      ("NULL", "null"),
      ("True", "true"),
      ("FALSE", "false"),
      ("01", "1"),
      ("+01", "1"),
      ("-01", "-1"),
      (".5", "0.5"),
      ("+.5", "0.5"),
      ("1.", "1"),
      ("1.e2", "100"),
      ("01e2", "100"),
      ("1e-400", "0"),
      ("0o10", "8"),
      ("0xFF", "255"),
      ("0x20000000000001", "9007199254740992"),
      ("0x20000000000003", "9007199254740996"),
      ("yes", "\"yes\""),
      ("on", "\"on\""),
      ("2026-09-06", "\"2026-09-06\""),
      ("+0x10", "\"+0x10\""),
      ("-0o10", "\"-0o10\""),
      ("0X10", "\"0X10\""),
      ("0b10", "\"0b10\""),
      ("1_000", "\"1_000\""),
      ("1e+", "\"1e+\""),
      ("'null'", "\"null\""),
      ("\"01\"", "\"01\""),
    ] {
    same_values(yaml(source), parsed(expected))
  }
  for source in ["-0", "-00", "-.0", "-0e30", "-1e-400"] {
    assert_eq(yaml_error(source).issue, NegativeZero)
  }
  for source in ["1e400", "-.inf", ".Inf", ".NAN", "0x" + "f".repeat(257)] {
    assert_eq(yaml_error(source).issue, NumberOutOfRange)
  }
  let long = "0." + "0".repeat(65535) + "1e655360"
  assert_eq(yaml_error(long).issue, NumberOutOfRange)
  same_values(yaml("0." + "0".repeat(65535) + "1e65536"), parsed("1"))
}

///|
test "YAML scalar decoding preserves values after YAML folding and escape interpretation" {
  for
    (source, expected) in [
      ("'it''s fine'", "it's fine"),
      (
        "\"\\0\\a\\b\\t\\n\\v\\f\\r\\e\\ \\\"\\/\\\\\\N\\_\\L\\P\"", "\u0000\u0007\b\t\n\u000b\f\r\u001b \"/\\\u0085\u00a0\u2028\u2029",
      ),
      ("\"\\x41\\u00E9\\U0001F600\"", "Aé😀"),
      ("\"e\\u0301\\r\\nX\\r\"", "e\u0301\r\nX\r"),
      ("\"one\n  two\"", "one two"),
      ("'one\n\n  two'", "one\ntwo"),
      ("\"one\\\n  two\"", "onetwo"),
      ("one\n  two\n\n  three", "one two\nthree"),
      ("|\n  # text\n  x:y\n", "# text\nx:y\n"),
      ("|-\n  one\n  two\n\n", "one\ntwo"),
      ("|+\n  one\n\n", "one\n\n"),
      (">\n  one\n  two\n", "one two\n"),
      (">-\n  one\n\n  two\n", "one\ntwo"),
      (">-\n  a\n\n    b\n", "a\n\n  b"),
      ("|2-\n   x\n", " x"),
      ("|\n  no final newline", "no final newline"),
      ("|\none\ntwo\n", "one\ntwo\n"),
      ("|1\n x\n  y\n", "x\n y\n"),
      ("'ﬁ\u2028\u0085'", "ﬁ\u2028\u0085"),
    ] {
    guard yaml(source).value is String(value) else { fail("expected string") }
    assert_eq(value, expected)
  }
  same_values(
    yaml("a: |\n  text\nb: >-\n  one\n  two\nc: true"),
    parsed("{\"a\":\"text\\n\",\"b\":\"one two\",\"c\":true}"),
  )
}

///|
test "YAML rejects graph features non-string keys collisions and extra documents" {
  for
    source in ["a: &id value", "a: *id", "a: !!str value", "<<: {}", "{<<: {}}"] {
    assert_eq(yaml_error(source).issue, ForbiddenYamlFeature)
  }
  for
    source in [
      "1: value", "true: value", "null: value", "{1: value}", "? [a, b]\n: value",
    ] {
    assert_eq(yaml_error(source).issue, NonStringKey)
  }
  for
    source in [
      "é: 1\n\"e\\u0301\": 2", "{a: 1, a: 2}", "\"x\\r\": 1\n\"x\\n\": 2",
    ] {
    assert_true(yaml_error(source).issue is DuplicateKey(_))
  }
  same_values(yaml("---\na: true\n...\n# done"), parsed("{\"a\":true}"))
  same_values(yaml("%YAML 1.2\n---\n[1, 2]"), parsed("[1,2]"))
  same_values(
    yaml("%YAML\t1.2\t# comment\n---\na: true"),
    parsed("{\"a\":true}"),
  )
  assert_true(yaml("---").value is Null)
  for source in ["a: 1\n---\na: 2", "---\n---", "a: 1\n...\n---\na: 2"] {
    assert_eq(yaml_error(source).issue, MultipleDocuments)
  }
  for
    source in [
      "[a,,b]", "{a: 1 b: 2}", "a:\n\tb: 1", "a: @bad", "\"\\q\"", "\"\\U00110000\"",
      "a: [1,\n2]", "a: \"x\"#bad", "[#bad\n]", "--- a: 1", "\ufeff\ufeffa: 1",
    ] {
    ignore(yaml_error(source))
  }
}

///|
test "YAML shares strict input checks and exact node and depth limits" {
  let source = "a: [1, {b: true}]"
  assert_true(
    parse_yaml(source, limits(bytes=source.length(), nodes=5, depth=3)) is Ok(_),
  )
  let cases : Array[(ParseLimits, ParseIssue)] = [
    (limits(bytes=source.length() - 1), InputLimit),
    (limits(nodes=4), NodeLimit),
    (limits(depth=2), DepthLimit),
    (limits(bytes=-1), InvalidLimits),
    (limits(nodes=-1), InvalidLimits),
  ]
  for (budget, expected) in cases {
    guard parse_yaml(source, budget) is Err(error) else {
      fail("expected budget rejection")
    }
    assert_eq(error.issue, expected)
  }
  assert_true(parse_yaml("true", limits(depth=0, nodes=1)) is Ok(_))
  assert_true(parse_yaml_bytes(b"\xef\xbb\xbfa: true", limits()) is Ok(_))
  guard parse_yaml_bytes(b"\xff", limits()) is Err(utf8) else {
    fail("expected UTF8 rejection")
  }
  assert_eq(utf8.issue, InvalidUtf8)
  let malformed = String::from_array([(0xD800).unsafe_to_char()])
  guard parse_yaml(malformed, limits()) is Err(utf16) else {
    fail("expected UTF16 rejection")
  }
  assert_eq(utf16.issue, InvalidUtf16)
}

///|
test "YAML spans retain original UTF8 coordinates and key paths" {
  let source = "\ufeffé: [\"😀\", false]\r\nx: 2"
  guard yaml(source).value is Object(fields) else { fail("expected object") }
  assert_eq(fields[0].key_span.start_byte, 3)
  assert_eq(fields[0].key_span.end_byte, 5)
  assert_eq(fields[0].key_span.start_column, 1)
  assert_eq(fields[0].key_span.end_column, 2)
  guard fields[0].value.value is Array(items) else { fail("expected array") }
  assert_eq(items[0].span.start_byte, 8)
  assert_eq(items[0].span.end_byte, 14)
  assert_eq(items[0].span.start_column, 5)
  assert_eq(items[0].span.end_column, 8)
  assert_eq(fields[1].key_span.start_line, 2)
  assert_eq(fields[1].key_span.start_column, 1)
  let error = yaml_error("a:\n  b: \"\\q\"")
  assert_eq(error.issue, InvalidEscape)
  assert_eq(error.path, Some([Key("a"), Key("b")]))
  guard error.location is Source(span) else { fail("expected source span") }
  assert_eq(span.start_byte, 10)
  assert_eq(span.end_byte, 11)
  guard yaml("a   : 1   # comment").value is Object(spaced) else {
    fail("expected object")
  }
  assert_eq(spaced[0].key_span.end_byte, 1)
  assert_eq(spaced[0].value.span.end_byte, 7)
}

///|
test "YAML flow and compact block nesting use explicit frames" {
  let depth = 10000
  let flow = "[".repeat(depth) + "true" + "]".repeat(depth)
  let block = "- ".repeat(depth) + "true"
  for source in [flow, block] {
    let mut value = parse_yaml(source, limits(nodes=depth + 1, depth~)).unwrap()
    for i = 0; i < depth; i = i + 1 {
      guard value.value is Array(items) else { fail("expected array") }
      assert_eq(items.length(), 1)
      value = items[0]
    }
    assert_true(value.value is Bool(true))
    guard parse_yaml(source, limits(depth=depth - 1)) is Err(error) else {
      fail("expected depth failure")
    }
    assert_eq(error.issue, DepthLimit)
  }
}
