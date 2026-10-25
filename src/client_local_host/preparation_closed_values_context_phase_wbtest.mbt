///|
test "ClosedValues context fixed normalization composes source and writers" {
  let small = closed_values_normalization_layout(4).unwrap()
  let large = closed_values_normalization_layout(100).unwrap()
  assert_true(preparation_representation_cost(small.retained).unwrap() > 0L)
  assert_true(
    preparation_representation_cost(large.temporary).unwrap() >=
    preparation_representation_cost(small.temporary).unwrap(),
  )
  assert_true(closed_values_normalization_layout(-1) is None)
  let source = closed_values_context_fixed_source(
    151, 4, 1, 1, 3, 5, 130, 71, 2,
  ).unwrap()
  assert_true(source.record_headers > 4L)
  assert_true(source.owned_utf16_units >= 130L)
}

///|
test "ClosedValues context core finite source owners and writer growth" {
  let facts : ClosedValuesLexicalFacts = {
    input_bytes: 98000,
    node_upper: 10500,
    objects: 107,
    arrays: 103,
    fields_upper: 310,
    quoted_tokens: 620,
    quoted_utf16_units: 2000,
    longest_quoted_utf16: 8,
    longest_atom_utf16: 5,
    depth_upper: 7,
  }
  let core = closed_values_context_core_layout(facts).unwrap()
  assert_true(preparation_representation_cost(core.retained).unwrap() > 0L)
  assert_true(core._observed_failure == core.temporary)
  let one = closed_values_operation_writer_layout(1, 1).unwrap()
  let many = closed_values_operation_writer_layout(100, 99).unwrap()
  assert_true(
    preparation_representation_cost(many).unwrap() >
    preparation_representation_cost(one).unwrap(),
  )
  assert_true(
    closed_values_operation_writer_layout(2147483647, 2147483647) is None,
  )
  assert_true(closed_values_writer_layout(-1, 0, 1, 0, 0) is None)
}

///|
test "ClosedValues context aggregate prices all finite families" {
  let schema : Array[String] = []
  let names : Array[String] = []
  for column in 0..<100 {
    let key = "v" + column.to_string()
    schema.push("\"" + key + "\":{\"type\":\"number\",\"nullable\":false}")
    names.push("\"" + key + "\"")
  }
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
  let document = "{\"version\":\"actql/0.1\",\"id\":\"closed\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{" +
    schema.join(",") +
    "},\"rows\":[" +
    rows.join(",") +
    "]},\"as\":\"v\"}],\"results\":{\"r\":{\"from\":\"v\",\"fields\":[" +
    names.join(",") +
    "]}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
  let facts = closed_values_lexical_facts(document, document.length()).unwrap()
  assert_true(facts.input_bytes > 65536)
  println(
    "context original bytes=\{facts.input_bytes} nodes=\{facts.node_upper} depth=\{facts.depth_upper}",
  )
  let quote = closed_values_context_components_layout(facts, 100, 99).unwrap()
  let retained = preparation_representation_cost(quote.retained).unwrap()
  let temporary = preparation_representation_cost(quote.temporary).unwrap()
  assert_true(retained > 0L && temporary > 0L)
  // Fixed original fixture: prior families855187 plus parsed witness source
  // envelope43516. This must stay under R after temporary phase completion.
  assert_eq(retained, 898703L)
  println("context representative retained=\{retained} temporary=\{temporary}")
  assert_true(closed_values_context_components_layout(facts, 0, 99) is None)
}
