///|
fn limits(
  bytes? : Int = 10000,
  nodes? : Int = 1000,
  depth? : Int = 100,
) -> ParseLimits {
  { max_input_bytes: bytes, max_nodes: nodes, max_depth: depth, }
}

///|
fn resumable_parse(
  text : String,
  bound : ParseLimits,
) -> Result[ParsedSource, ParseError] raise {
  let parser = start_json_parse(text, bound, source_path="steps.json").unwrap()
  for _ in 0..<100000 {
    match advance_json_parse(parser, 1).unwrap() {
      JsonParseContinue(work~) => assert_true(work > 0 && work <= 1)
      JsonParseComplete(parsed, work~) => {
        assert_true(work > 0 && work <= 1)
        assert_true(advance_json_parse(parser, 1) is Err(Terminal))
        cancel_json_parse(parser)
        return Ok(parsed)
      }
      JsonParseFailed(error, work~) => {
        assert_true(work > 0 && work <= 1)
        assert_true(advance_json_parse(parser, 1) is Err(Terminal))
        return Err(error)
      }
    }
  }
  cancel_json_parse(parser)
  fail("resumable parser did not terminate")
}

///|
test "resumable JSON preserves source order, spans, raw strings and usage" {
  let text = "{\"z\":[null,2],\"a\":{\"name\":\"raw\\r\\n\"}}"
  let parsed = resumable_parse(text, limits()).unwrap()
  assert_eq(parsed.usage, { input_bytes: text.length(), nodes: 6, depth: 2, })
  assert_eq(parsed.node.span.start_byte, 0)
  assert_eq(parsed.node.span.end_byte, text.length())
  guard parsed.node.value is Object(fields) else { fail("object") }
  assert_eq(fields.map(f => f.key), ["z", "a"])
  guard fields[0].value.value is Array(items) else { fail("array") }
  assert_true(items[0].value is Null)
  assert_true(items[1].value is Number(2))
  guard fields[1].value.value is Object(nested) else { fail("object") }
  assert_eq(nested[0].key, "name")
  assert_true(nested[0].value.value is String("raw\r\n"))
}

///|
test "resumable JSON preserves duplicate normalization and encoding error precedence" {
  for text in ["{\"é\":1,\"é\":2}", "[1,]", "{} {}", "\ufeff\ufeff{}"] {
    let expected = parse_json_measured(text, limits(), source_path="steps.json")
    guard expected is Err(error) else { fail("expected rejection") }
    assert_eq(resumable_parse(text, limits()).unwrap_err(), error)
  }
  let high = String::from_array([(0xd800).unsafe_to_char()])
  for bound in [limits(), limits(bytes=0)] {
    let text = "?" + high
    assert_eq(
      resumable_parse(text, bound).unwrap_err(),
      parse_json_measured(text, bound, source_path="steps.json").unwrap_err(),
    )
  }
}

///|
test "resumable JSON limits and cancellation retain no partial tree" {
  for bound in [limits(nodes=2), limits(depth=1), limits(bytes=4)] {
    let text = "[[1]]"
    assert_eq(
      resumable_parse(text, bound).unwrap_err(),
      parse_json_measured(text, bound, source_path="steps.json").unwrap_err(),
    )
  }
  let parser = start_json_parse("[1,2,3]", limits()).unwrap()
  assert_true(advance_json_parse(parser, 0) is Err(InvalidQuantum))
  assert_true(advance_json_parse(parser, 1) is Ok(JsonParseContinue(..)))
  cancel_json_parse(parser)
  cancel_json_parse(parser)
  assert_true(advance_json_parse(parser, 1) is Err(Terminal))
  assert_true(parser.document.frames.is_empty())
  assert_true(parser.document.completed is None)
  assert_eq(parser.document.parser.source, "")
}
