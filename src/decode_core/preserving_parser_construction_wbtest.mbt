///|
test "preserving byte parser retains the Source key inventory once plus its decoded input" {
  for
    (bytes, nodes, depth) in [
      (4096, 1000, 2),
      (4096, 1000, 1000),
      (64, 1, 1),
      (2147483647, 2147483647, 2147483647),
    ] {
    let literal = @source.json_literal_construction_extent(bytes, nodes, depth).unwrap()
    let parser = preserving_json_parser_construction_inventory(
      bytes, nodes, depth,
    ).unwrap()
    assert_eq(parser.record_headers, literal.record_headers + 1L)
    assert_eq(parser.reference_slots, literal.reference_slots)
    assert_eq(parser.scalar_words, literal.scalar_words)
    assert_eq(
      parser.owned_utf16_units,
      literal.owned_utf16_units + bytes.to_int64(),
    )
  }
}

///|
test "preserving byte parser inventory keeps invalid limits and actual node depth UTF8 refusals" {
  for
    (bytes, nodes, depth) in [
      (0, 1, 1),
      (1, 0, 1),
      (1, 1, 0),
      (-1, 1, 1),
      (1, -1, 1),
      (1, 1, -1),
    ] {
    assert_true(
      preserving_json_parser_construction_inventory(bytes, nodes, depth) is None,
    )
  }
  assert_true(
    @source.parse_json_bytes_preserving(b"[null,null]", {
      max_input_bytes: 64,
      max_nodes: 2,
      max_depth: 4,
    })
    is Err({ issue: NodeLimit, .. }),
  )
  assert_true(
    @source.parse_json_bytes_preserving(b"[[]]", {
      max_input_bytes: 64,
      max_nodes: 4,
      max_depth: 1,
    })
    is Err({ issue: DepthLimit, .. }),
  )
  assert_true(
    @source.parse_json_bytes_preserving(b"\xff", {
      max_input_bytes: 64,
      max_nodes: 4,
      max_depth: 4,
    })
    is Err({ issue: InvalidUtf8, .. }),
  )
}
