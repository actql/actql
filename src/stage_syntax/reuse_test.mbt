///|
test "parsed Program reuse checks independently measured retention limits" {
  let body = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{\"from\":\"generated\"}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
  let document = "\uFEFF" + body + " \r\n"
  let program = parsed(document, format=Json)
  // Sixteen value nodes, five nested containers, and 85 UTF-8 bytes across
  // field names and text values. The BOM and suffix contribute six raw bytes.
  assert_eq(program_usage(program), {
    source: { input_bytes: body.length() + 6, nodes: 16, depth: 5, },
    tree: {
      nodes: 16,
      depth: 5,
      largest_string_bytes: 9,
      total_string_bytes: 85,
    },
    stages: 1,
  })
  let exact = limits(
    bytes=body.length() + 6,
    nodes=16,
    depth=5,
    tree_nodes=16,
    tree_depth=5,
    string_bytes=9,
    total_bytes=85,
    stage_count=1,
  )
  assert_eq(validate_reuse(program, exact), Ok(()))
  assert_eq(parse(document, exact, format=Json).unwrap().id, program.id)
  for
    (small, expected) in [
      (limits(bytes=body.length() + 5), RetentionLimit::InputBytes),
      (limits(nodes=15), SourceNodes),
      (limits(depth=4), SourceDepth),
      (limits(tree_nodes=15), TreeNodes),
      (limits(tree_depth=4), TreeDepth),
      (limits(string_bytes=8), StringBytes),
      (limits(total_bytes=84), TotalStringBytes),
      (limits(stage_count=0), Stages),
    ] {
    assert_eq(
      validate_reuse(program, small),
      Err(RetentionLimit(expected, source_path="program.aql")),
    )
    assert_true(parse(document, small, format=Json) is Err(_))
  }
  assert_eq(validate_reuse(program, limits(bytes=-1)), Err(InvalidLimits))
  assert_eq(validate_reuse(program, exact), Ok(()))
}

///|
test "YAML and byte Program inputs retain measurements without losing source ownership" {
  let text = source() + "\n# trailing comment\n"
  let a = parsed(text)
  let b = parse_bytes(@utf8.encode(text), limits(), source_path="program.aql").unwrap()
  assert_eq(program_usage(a), program_usage(b))
  assert_eq(program_usage(a).source.input_bytes, @utf8.encode(text).length())
  assert_eq(program_usage(a).stages, 3)
  let root = program_body(a)
  assert_eq(validate_reuse(a, limits()), Ok(()))
  assert_true(physical_equal(program_body(a), root))
  assert_true(!physical_equal(program_body(a), program_body(b)))
}
