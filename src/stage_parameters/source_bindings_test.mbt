///|
fn source_binding_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 10,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
test "Source reuses only the original complete Program under compatible declaration bounds" {
  let program = parsed()
  let original = prepared(program)
  let caps : @parameter.DeclarationLimits = {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }
  let same = prepare(
    program,
    { ..caps, max_nodes: 1001, },
    original=Some(original),
  ).unwrap()
  assert_true(physical_equal(original, same))
  assert_true(physical_equal(declarations(original), declarations(same)))
  let foreign = prepare(parsed(), caps, original=Some(original)).unwrap()
  assert_true(!physical_equal(declarations(original), declarations(foreign)))
  assert_true(
    prepare(program, { ..caps, max_nodes: 0, }, original=Some(original))
    is Err(_),
  )
  assert_true(
    prepare(program, { ..caps, max_parameters: -1, }, original=Some(original))
    is Err(_),
  )
}

///|
test "Source completed binding retains original values under measured fitting limits and refuses changed inputs" {
  let original = prepared(parsed())
  let supplied = Some(source_binding_cursor("{\"n\":7}"))
  let caps : @value.Limits = {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }
  let (source, first) = prepare_bindings(original, supplied, caps)
  guard first is Ok(Ready(values)) else { fail("original binding") }
  let repeated = bind(source, supplied, { ..caps, max_nodes: 101, }).unwrap()
  guard repeated is Ready(same) else { fail("completed original") }
  assert_true(physical_equal(values, same))
  let exact = { ..caps, max_nodes: 1, max_text_bytes: 1, }
  guard bind(source, supplied, exact) is Ok(Ready(same)) else {
    fail("same Source must consume its completed measured binding")
  }
  assert_true(physical_equal(values, same))
  let (same_source, exact_result) = prepare_bindings(source, supplied, exact)
  assert_true(physical_equal(source, same_source))
  guard exact_result is Ok(Ready(same)) else { fail("measured repeat") }
  assert_true(physical_equal(values, same))
  let (same_source, same_result) = prepare_bindings(source, supplied, caps)
  assert_true(physical_equal(source, same_source))
  guard same_result is Ok(Ready(same)) else { fail("original repeat") }
  assert_true(physical_equal(values, same))
  let changed = bind(source, Some(source_binding_cursor("{\"n\":8}")), caps).unwrap()
  guard changed is Ready(other) else { fail("changed binding") }
  assert_true(!physical_equal(values, other))
  assert_true(
    @parameter.bound_value_at(other, 0).unwrap().value.value is Number(8.0),
  )
  assert_true(bind(source, supplied, { ..caps, max_nodes: 0, }) is Err(_))
  assert_true(bind(source, None, caps) is Ok(NeedsBindings(_)))
  assert_true(
    bind(source, Some(source_binding_cursor("{\"n\":null}")), caps) is Err(_),
  )
}
