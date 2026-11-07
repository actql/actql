///|
fn observed_source_fixture(
  text : String,
  bounds : ParseLimits,
) -> (JsonSourcePreflight, JsonSourceGeometry) raise {
  let original = start_program_json_source_preflight(text, bounds).unwrap()
  while true {
    match advance_json_source_preflight(original, 64).unwrap() {
      JsonSourceContinue(..) => continue
      JsonSourceReady(actual, ..) => return (original, actual)
      JsonSourceFailed(_, ..) =>
        fail("the fixture's original Unicode must admit")
    }
  } nobreak {
    fail("the fixture's original preflight must finish")
  }
}

///|
fn observed_source_parse(
  original : JsonSourcePreflight,
) -> Result[ParsedSource, ParseError] raise {
  let cursor = take_json_source_parser(original).unwrap()
  while true {
    match advance_json_parse(cursor, 64).unwrap() {
      JsonParseContinue(..) => continue
      JsonParseComplete(parsed, ..) => return Ok(parsed)
      JsonParseFailed(issue, ..) => return Err(issue)
    }
  } nobreak {
    fail("the same original parser must finish")
  }
}

///|
test "observed Source quote keeps canonical Unicode escaped keys and original parser refusals" {
  let bounds = { max_input_bytes: 1000000, max_nodes: 10000, max_depth: 64, }
  let text = "{\"e\\u0301\":\"日😀\\\\\\n\"}"
  let (original, actual) = observed_source_fixture(text, bounds)
  assert_eq(actual.fields, 1)
  assert_eq(actual.objects, 1)
  assert_eq(actual.arrays, 0)
  assert_true(actual.longest_quoted_raw_utf16 >= 7)
  assert_true(
    json_source_geometry_construction_extent(
      actual,
      actual.node_upper,
      actual.depth_upper,
    )
    is Some(_),
  )
  let parsed = observed_source_parse(original).unwrap()
  guard parsed.node.value is Object(fields) else { fail("original object") }
  assert_eq(fields[0].key, "é")
  guard fields[0].value.value is String(value) else { fail("original Text") }
  assert_eq(value, "日😀\\\n")
  for
    (text, selected, issue) in [
      ("{\"é\":1,\"e\\u0301\":2}", bounds, DuplicateKey("é")),
      ("[[]]", { ..bounds, max_depth: 1, }, DepthLimit),
      ("[null]", { ..bounds, max_nodes: 1, }, NodeLimit),
    ] {
    let (original, actual) = observed_source_fixture(text, selected)
    assert_true(
      json_source_geometry_construction_extent(
        actual,
        Int::max(1, Int::min(actual.node_upper, selected.max_nodes)),
        Int::max(1, Int::min(actual.depth_upper, selected.max_depth)),
      )
      is Some(_),
    )
    assert_eq(observed_source_parse(original).unwrap_err().issue, issue)
  }
}

///|
test "observed Source quote separates single-key workspace from whole document and rejects invalid geometry" {
  let bounds = { max_input_bytes: 1000000, max_nodes: 10000, max_depth: 64, }
  let text = "{\"name\":\"" + String::make(10000, '日') + "😀\"}"
  let (original, actual) = observed_source_fixture(text, bounds)
  // A long value remains a small tree. No quoted spelling is assumed ASCII;
  // the same canonical scratch and output owners supply Unicode expansion.
  assert_true(actual.node_upper < 10)
  let quote = json_source_geometry_construction_extent(
    actual,
    actual.node_upper,
    actual.depth_upper,
  ).unwrap()
  let generic = json_source_grammar_construction_extent(
    actual.input_bytes,
    actual.node_upper,
    actual.depth_upper,
  ).unwrap()
  assert_true(quote.scalar_words < generic.scalar_words)
  assert_true(
    json_source_geometry_construction_extent(
      { ..actual, quoted_raw_utf16_units: -1, },
      1,
      1,
    )
    is None,
  )
  assert_true(json_source_geometry_construction_extent(actual, 0, 1) is None)
  assert_true(json_source_geometry_construction_extent(actual, 1, 0) is None)
  let parsed = observed_source_parse(original).unwrap()
  assert_eq(parsed.usage.nodes, 2)
}
