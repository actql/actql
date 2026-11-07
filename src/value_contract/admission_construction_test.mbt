///|
test "original read inventory uses selected identifier fields not enum or MIME DATA length" {
  let huge = String::make(10000, 'x')
  let wire = "{\"type\":\"string\",\"nullable\":false,\"enum\":[\"" +
    huge +
    "\"]}"
  let original = cursor(wire)
  let geometry = @value_contract.observe_read_construction_geometry(original)
  assert_eq(geometry.nodes, 5)
  assert_eq(geometry.max_selected_text_units, 8)
  let (result, nodes, text) = @value_contract.observe_checked_usage(
    original,
    limits(),
  )
  let (contract, n, t) = result.unwrap()
  assert_eq((nodes, text), (3, 10006))
  assert_eq((n, t), (nodes, text))
  guard contract.shape is Text(bounds) else { fail("Text contract") }
  assert_eq(@value_contract.text_enumerant_at(bounds, 0), Some(huge))
  let media = cursor(
    "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"text/plain; p=" +
    huge +
    "\"}",
  )
  assert_eq(
    @value_contract.observe_read_construction_geometry(media).max_selected_text_units,
    11,
  )
  assert_true(@value_contract.read_checked(media, limits()) is Ok(_))
  let resource = cursor(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"" +
    huge +
    "\"}",
  )
  assert_eq(
    @value_contract.observe_read_construction_geometry(resource).max_selected_text_units,
    10000,
  )
  assert_true(@value_contract.read_checked(resource, limits()) is Ok(_))
}

///|
test "shared read construction independent primitive vector and full Int geometry remain bounded" {
  let geometry = @value_contract.observe_read_construction_geometry(
    cursor("{\"type\":\"number\",\"nullable\":false}"),
  )
  let v = @value_contract.read_construction_inventory(geometry).unwrap()
  // Source body3nodes/2fields, max identifier8, root ancestry0.
  assert_true(
    v.retained ==
    { record_headers: 24L, reference_slots: 57L, scalar_words: 21L, },
  )
  assert_eq(v.scratch, {
    record_headers: 340L,
    reference_slots: 589L,
    scalar_words: 1121L,
  })
  assert_eq(v.scratch_utf16_units, 162L)
  assert_true(
    @value_contract.read_construction_inventory({
      ..geometry,
      nodes: 2147483647,
      fields: 2147483646,
      max_fields: 2147483646,
      max_selected_text_units: 2147483647,
    })
    is Some(_),
  )
  assert_true(
    @value_contract.read_construction_inventory({ ..geometry, nodes: 0, })
    is None,
  )
  assert_true(
    @value_contract.read_construction_inventory({ ..geometry, max_fields: 3, })
    is None,
  )
}

///|
test "same original checked meter retains exact partial typed refusal and limit order" {
  let original = cursor(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"unknown\",\"nullable\":false}}",
  )
  let (observed, nodes, text) = @value_contract.observe_checked_usage(
    original,
    limits(),
  )
  let old = @value_contract.read_checked_usage(original, limits()).unwrap_err()
  assert_true(observed is Err(issue) && issue == old)
  assert_eq((nodes, text), (2, 12))
  let (short, nodes, text) = @value_contract.observe_checked_usage(
    original,
    limits(nodes=1),
  )
  assert_true(short is Err(ContractIssue(BudgetExceeded, ..)))
  assert_eq((nodes, text), (1, 5))
  let (invalid, nodes, text) = @value_contract.observe_checked_usage(
    original,
    limits(nodes=-1),
  )
  assert_true(invalid is Err(InvalidLimits))
  assert_eq((nodes, text), (0, 0))
}
