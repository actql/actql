///|
test "closed Values lexical envelope bounds original parser tree without accepting grammar" {
  for
    text in [
      "null", "[]", "{}", "[1,2,3]", "{\"x\":[1,2],\"y\":{\"z\":false}}", "{\"colon:comma,brace{}\":\"text\"}",
    ] {
    let facts = closed_values_lexical_facts(text, text.length()).unwrap()
    let parsed = @source.parse_json(text, {
      max_input_bytes: facts.input_bytes,
      max_nodes: facts.node_upper,
      max_depth: facts.depth_upper,
    }).unwrap()
    let actual = @source.representation_extent(
      parsed,
      facts.node_upper,
      facts.depth_upper,
      100000,
    ).unwrap()
    assert_true(actual.nodes <= facts.node_upper.to_int64())
    assert_true(actual.fields <= facts.fields_upper.to_int64())
    assert_eq(actual.arrays, facts.arrays.to_int64())
    assert_eq(actual.objects, facts.objects.to_int64())
    assert_true(closed_values_lexical_facts(text, text.length() - 1) is None)
  }
  // Envelope facts never replace the authoritative JSON grammar.
  let invalid = "{[true]}"
  assert_true(closed_values_lexical_facts(invalid, invalid.length()) is Some(_))
  assert_true(
    @source.parse_json(invalid, {
      max_input_bytes: 100,
      max_nodes: 100,
      max_depth: 10,
    })
    is Err(_),
  )
  assert_true(closed_values_lexical_facts("\"列\"", 100) is None)
  assert_true(closed_values_lexical_facts("\"a\\nb\"", 100) is None)
  assert_true(closed_values_lexical_facts("[", 100) is None)
}

///|
test "closed Values lexical envelope scales beyond the old source byte ceiling" {
  let rows : Array[String] = []
  for row in 0..<99 {
    let cells : Array[String] = []
    for column in 0..<100 {
      cells.push(
        "\"v" + column.to_string() + "\":" + (row + column).to_string(),
      )
    }
    rows.push("{" + cells.join(",") + "}")
  }
  let text = "[" + rows.join(",") + "]"
  assert_true(text.length() > 65536)
  let facts = closed_values_lexical_facts(text, text.length()).unwrap()
  assert_eq(facts.objects, 99)
  assert_eq(facts.arrays, 1)
  assert_eq(facts.fields_upper, 9900)
  assert_eq(facts.quoted_tokens, 9900)
  assert_eq(facts.depth_upper, 2)
  let parsed = @source.parse_json(text, {
    max_input_bytes: facts.input_bytes,
    max_nodes: facts.node_upper,
    max_depth: facts.depth_upper,
  }).unwrap()
  let actual = @source.representation_extent(
    parsed,
    facts.node_upper,
    facts.depth_upper,
    1000000,
  ).unwrap()
  assert_eq(actual.nodes, 10000L)
  assert_true(actual.nodes <= facts.node_upper.to_int64())
}

///|
test "closed Values source phases keep shared spans and sequential scratch distinct" {
  let text = "{\"a\":[1,2,3],\"b\":\"value\"}"
  let facts = closed_values_lexical_facts(text, text.length()).unwrap()
  let inventories = closed_values_source_inventories(facts)
  let source = @execution.preparation_representation_cost(
    inventories.source_retained,
  ).unwrap()
  let shared = @execution.preparation_representation_cost(
    inventories.source_shared_dependencies,
  ).unwrap()
  let indexed = @execution.preparation_representation_cost(
    inventories.indexed_additional,
  ).unwrap()
  assert_true(source > shared)
  assert_true(indexed > 0L)
  assert_eq(inventories.indexed_additional.owned_utf16_units, 0L)
  assert_eq(
    inventories.source_shared_dependencies.owned_utf16_units,
    inventories.source_retained.owned_utf16_units,
  )
  assert_true(
    @execution.preparation_representation_cost(inventories.key_admission_peak).unwrap() >
    0L,
  )
  assert_true(
    @execution.preparation_representation_cost(inventories.parser_controls_peak).unwrap() >
    0L,
  )
  assert_true(
    @execution.preparation_representation_cost(
      inventories.decoder_controls_peak,
    ).unwrap() >
    0L,
  )
}
