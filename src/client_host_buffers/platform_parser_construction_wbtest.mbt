///|
// Public Local settings shape only: eight file descriptions and the retained
// managed root. No Installation, file descriptor, VM or physical ACK is issued.
test "platform parser prices the public shallow settings envelope from the same Source inventory" {
  let files : Array[String] = []
  for
    name in [
      "retention.json", "retention-policy.json", "store.json", "result-policy.json",
      "environment.json", "compute.json", "run-policy-profile.json", "sdk-read.json",
    ] {
    files.push(
      "{\"name\":\"" +
      name +
      "\",\"body\":\"{}\",\"device\":\"1\",\"inode\":\"2\",\"size\":\"2\"}",
    )
  }
  let text = "{\"files\":[" +
    files.join(",") +
    "],\"managed_root\":{\"device\":\"1\",\"inode\":\"3\",\"path\":\"results\"}}"
  let limits : @source.ParseLimits = {
    max_input_bytes: 8192,
    max_nodes: 1024,
    max_depth: 16,
  }
  let preflight = @source.start_json_source_preflight(
    text,
    limits,
    data_keys=true,
  ).unwrap()
  let mut observed = None
  while observed is None {
    match @source.advance_json_source_preflight(preflight, 64).unwrap() {
      @source.JsonSourceContinue(..) => ()
      @source.JsonSourceFailed(_, ..) =>
        fail("Original public settings preflight")
      @source.JsonSourceReady(geometry, ..) => observed = Some(geometry)
    }
  }
  let geometry = observed.unwrap()
  assert_eq(geometry.objects, files.length() + 2)
  assert_eq(geometry.arrays, 1)
  assert_eq(geometry.fields, files.length() * 5 + 5)
  assert_eq(geometry.depth_upper, 3)
  // Use the actual preflight bounds consumed by the platform parser. The
  // scalar node cap is not substituted for that original shallow geometry.
  let bytes = Int::max(1, geometry.input_bytes)
  let nodes = Int::max(1, Int::min(limits.max_nodes, geometry.node_upper))
  let depth = Int::max(1, Int::min(limits.max_depth, geometry.depth_upper))
  let literal = @source.json_literal_construction_extent(bytes, nodes, depth).unwrap()
  let expected = @execution.preparation_representation_cost({
    record_headers: literal.record_headers + 1L,
    reference_slots: literal.reference_slots,
    scalar_words: literal.scalar_words,
    owned_utf16_units: literal.owned_utf16_units + bytes.to_int64(),
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(
    platform_input_parser_bytes(geometry, limits.max_nodes, limits.max_depth),
    Some(expected),
  )
  let parser = @source.take_json_source_parser(preflight).unwrap()
  let mut completed = None
  while completed is None {
    match @source.advance_json_parse(parser, 64).unwrap() {
      @source.JsonParseContinue(..) => ()
      @source.JsonParseFailed(_, ..) => fail("Original public settings parser")
      @source.JsonParseComplete(parsed, ..) => completed = Some(parsed.node)
    }
  }
  guard completed is Some({ value: Object(root), .. }) else {
    fail("Original settings object")
  }
  guard root[0].value.value is Array(restored) else {
    fail("Original file descriptions")
  }
  assert_eq(restored.length(), files.length())
}
