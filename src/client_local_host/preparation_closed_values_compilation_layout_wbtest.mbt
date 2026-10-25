///|
test "compilation composed quote includes original numeric 100k source and checked metadata" {
  let rows : Array[String] = []
  for i in 0..<100000 {
    rows.push("{\"v0\":" + i.to_string() + "}")
  }
  let source = "{\"version\":\"actql/0.1\",\"id\":\"numeric-scale\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"v\",\"values\":{\"schema\":{\"v0\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows.join(",") +
    "]}}],\"results\":{\"rows\":{\"from\":\"v\",\"fields\":[\"v0\"]}}}],\"results\":{\"answer0\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let facts = closed_values_lexical_facts(source, source.length()).unwrap()
  assert_eq(facts.input_bytes, 1289175)
  let layout = closed_values_compilation_layout(facts, 1, 100000).unwrap()
  assert_true(layout.max_nodes > 200000)
  assert_eq(layout.max_facts, 2)
  assert_eq(facts.quoted_utf16_units.to_int64() / (100000L + 1L), 2L)
  assert_true(layout.max_wire_bytes < 6000000)
  assert_true(layout.max_nodes > 500000)
  assert_eq(layout.max_witnesses, 3)
  println(
    "COMPILATION_100K " +
    preparation_representation_cost(layout.retained).unwrap().to_string() +
    " " +
    preparation_representation_cost(layout.temporary).unwrap().to_string() +
    " B=" +
    layout.max_wire_bytes.to_string() +
    " N=" +
    layout.max_nodes.to_string() +
    " D=" +
    layout.max_depth.to_string(),
  )
  let meta = closed_values_compilation_metadata_layout(
    1,
    facts.longest_quoted_utf16,
  ).unwrap()
  let pipeline = compilation_pipeline_shape(
    1,
    100000,
    facts.longest_quoted_utf16,
    8,
  ).unwrap()
  let fragment = compilation_fragment_shape(pipeline.facts, 8).unwrap()
  let graph = compilation_add_wire_shapes(fragment, meta.graph_extra, 9).unwrap()
  let material = compilation_add_wire_shapes(
    facts,
    meta.material_extra,
    facts.depth_upper + 1,
  ).unwrap()
  let parsed = [
    compilation_parse_layout(pipeline.facts, 4).unwrap(),
    compilation_parse_layout(fragment, 6).unwrap(),
    compilation_parse_layout(facts, 4).unwrap(),
    compilation_parse_layout(material, 14).unwrap(),
    compilation_parse_layout(graph, 14).unwrap(),
  ]
  for i in 0..<parsed.length() {
    println(
      "PARSE " +
      i.to_string() +
      " " +
      preparation_representation_cost(parsed[i].value).unwrap().to_string() +
      " " +
      preparation_representation_cost(parsed[i].temporary).unwrap().to_string(),
    )
  }
  println(
    "META " +
    preparation_representation_cost(meta.temporary).unwrap().to_string(),
  )
  println(
    "WRITER " +
    preparation_representation_cost(
      closed_values_writer_layout(
        layout.max_nodes,
        layout.max_depth,
        1,
        1,
        layout.max_wire_bytes,
      ).unwrap(),
    )
    .unwrap()
    .to_string(),
  )
  println(
    "PROGRAM " +
    preparation_representation_cost(
      compilation_program_emitter_layout(facts, 4).unwrap(),
    )
    .unwrap()
    .to_string(),
  )
  assert_true(closed_values_compilation_layout(facts, 0, 100000) is None)
}

///|
test "compilation composed zero rows preserves name bound and rejects unrepresentable products" {
  let source = "{\"version\":\"actql/0.1\",\"id\":\"zero\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"v\",\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]}}],\"results\":{\"rows\":{\"from\":\"v\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let facts = closed_values_lexical_facts(source, source.length()).unwrap()
  let layout = closed_values_compilation_layout(facts, 1, 0).unwrap()
  assert_true(layout.max_wire_bytes > source.length())
  assert_true(layout.max_nodes > facts.node_upper)
  assert_true(
    closed_values_compilation_layout(facts, 2147483647, 2147483647) is None,
  )
}
