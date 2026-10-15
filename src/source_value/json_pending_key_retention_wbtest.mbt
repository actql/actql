///|
// Observe the existing private document before its public cancellation clears
// the same parser. This is an allocation-lifetime witness, not a capacity grant.
fn pending_funding_document_failure(
  document : JsonDocument,
) -> ParseError raise {
  for _ in 0..<512 {
    let completed = document.step() catch { ParseAbort(error) => return error }
    assert_true(completed is None)
  }
  fail("bounded pending-key fixture did not fail")
}

///|
test "pending key is retained before the next value node is admitted" {
  let text = "{\"a\":null,\"b\":null}"
  let parser = Parser::make(
    text,
    "pending-key.json",
    limits(nodes=2, depth=1),
    normalize_text=false,
  )
  let document = JsonDocument::make(parser)
  let error = pending_funding_document_failure(document)
  assert_eq(error.issue, NodeLimit)
  assert_eq(parser.nodes, 2)
  assert_eq(document.frames.length(), 1)
  assert_true(document.completed is None)
  let frame = document.frames[0]
  guard frame.container is ObjectFields(fields, keys) else {
    fail("original object frame missing")
  }
  assert_eq(fields.length(), 1)
  assert_eq(fields[0].key, "a")
  assert_true(fields[0].value.value is Null)
  assert_eq(frame.key.map(pair => pair.0), Some("b"))
  // Both exact keys already belong to the original duplicate-key owner, even
  // though only one completed Field exists. Duplicate probes add no entries.
  assert_true(!@shape.admit_key(keys, "a"))
  assert_true(!@shape.admit_key(keys, "b"))
  assert_eq(parser.path, [Key("b")])
  assert_eq(error.path, Some([Key("b")]))
  assert_true(!physical_equal(parser.path, error.path.unwrap()))
  guard error.location is Source(span) else { fail("source location missing") }
  assert_eq(span.start_byte, 14)
  assert_eq(span.end_byte, 14)
  assert_eq(span.source_path, "pending-key.json")
}

///|
test "unfinished container owners survive the depth failure before a source tree exists" {
  let text = "{\"outer\":{\"inner\":{\"leaf\":null}}}"
  let parser = Parser::make(
    text,
    "pending-depth.json",
    limits(nodes=4, depth=2),
    normalize_text=false,
  )
  let document = JsonDocument::make(parser)
  let error = pending_funding_document_failure(document)
  assert_eq(error.issue, DepthLimit)
  assert_eq(parser.nodes, 3)
  assert_eq(document.frames.length(), 2)
  assert_true(document.completed is None)
  for (index, name) in ["outer", "inner"].iter().enumerate() {
    let frame = document.frames[index]
    guard frame.container is ObjectFields(fields, keys) else {
      fail("unfinished original container missing")
    }
    assert_true(fields.is_empty())
    assert_eq(frame.key.map(pair => pair.0), Some(name))
    assert_true(!@shape.admit_key(keys, name))
  }
  assert_eq(error.path, Some([Key("outer"), Key("inner")]))
  assert_true(!physical_equal(parser.path, error.path.unwrap()))
  guard error.location is Source(span) else { fail("source location missing") }
  assert_eq(span.start_byte, 18)
  assert_eq(span.end_byte, 18)
}

///|
test "one-short resumed failure keeps its detached path after original parser cleanup" {
  let text = "{\"a\":null,\"b\":null}"
  let cursor = start_json_parse(
    text,
    limits(nodes=2, depth=1),
    source_path="pending-resumed.json",
    data_keys=true,
  ).unwrap()
  let mut failure : ParseError? = None
  let mut transitions = 0
  for _ in 0..<512 {
    transitions += 1
    match advance_json_parse(cursor, 1).unwrap() {
      JsonParseContinue(work~) => assert_eq(work, 1)
      JsonParseComplete(..) => fail("one-short parser published a tree")
      JsonParseFailed(error, work~) => {
        assert_eq(work, 1)
        failure = Some(error)
        break
      }
    }
  }
  assert_true(transitions > 1)
  guard failure is Some(error) else { fail("one-short failure missing") }
  assert_eq(error.issue, NodeLimit)
  assert_eq(error.path, Some([Key("b")]))
  assert_true(cursor.document.frames.is_empty())
  assert_true(cursor.document.parser.path.is_empty())
  assert_true(cursor.document.completed is None)
  assert_eq(cursor.document.parser.source, "")
  cancel_json_parse(cursor)
  assert_true(advance_json_parse(cursor, 1) is Err(Terminal))
  assert_eq(error.path, Some([Key("b")]))
  let exact = parse_json_measured(
    text,
    limits(nodes=3, depth=1),
    source_path="pending-exact.json",
  ).unwrap()
  assert_eq(exact.usage, { input_bytes: 19, nodes: 3, depth: 1, })
  guard exact.node.value is Object(fields) else { fail("exact object missing") }
  assert_eq(fields.map(field => field.key), ["a", "b"])
}
