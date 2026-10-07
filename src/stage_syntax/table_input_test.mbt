///|
fn table_program(effect : String, exports? : String = "rows") -> Program raise {
  let text = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"rows\":{}},\"table_inputs\":{\"material\":{\"from\":\"binding\",\"fields\":[\"id\",\"p\"]}},\"effects\":{\"save\":" +
    effect +
    "}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"s\",\"result\":\"" +
    exports +
    "\"}}}}"
  parsed(text, format=Json)
}

///|
test "Store headers retain private Table input without a public Result source" {
  let effect =
    #|{"store":{"target":"connector://table/catalog","mapping":"mapping:table.catalog.v1","from":{"table_input":"material"}}}
  let document = table_program(effect)
  let header = effect_header_at(
    collect_effect_headers(document, 1, 1).unwrap(),
    0,
  ).unwrap()
  assert_eq(effect_header_source_table_input(header), Some("material"))
  assert_eq(effect_header_source_result(header), None)
  assert_eq(effect_header_kind(header), "store")
  let out = @encode.writer(10000, 1000, 30)
  emit_effect_header_semantics(header, out)
  let wire = @encode.finish(out)
  assert_eq(
    wire, "{\"body\":{\"from\":{\"table_input\":\"material\"},\"mapping\":\"mapping:table.catalog.v1\",\"target\":\"connector://table/catalog\"},\"failure_policy\":\"halt\",\"kind\":\"store\",\"source_result\":null,\"source_table_input\":\"material\"}",
  )
}

///|
test "private Table inputs cannot masquerade as ordinary Results or other Effects" {
  let good =
    #|{"store":{"target":"connector://table/catalog","mapping":"mapping:table.catalog.v1","from":{"table_input":"material"}}}
  assert_true(
    try {
      let _ = table_program(good, exports="material")
      false
    } catch {
      _ => true
    },
  )
  for
    effect in [
      "{\"store\":{\"target\":\"connector://table/catalog\",\"mapping\":\"mapping:table.catalog.v1\",\"from\":{\"result\":\"material\"}}}",
      "{\"store\":{\"target\":\"connector://table/catalog\",\"mapping\":\"mapping:table.catalog.v1\",\"from\":{\"table_input\":\"unknown\"}}}",
      "{\"store\":{\"target\":\"connector://table/catalog\",\"mapping\":\"mapping:table.catalog.v1\",\"from\":{\"result\":\"rows\",\"table_input\":\"material\"}}}",
      "{\"store\":{\"target\":\"connector://table/catalog\",\"mapping\":\"mapping:table.catalog.v1\",\"from\":{\"table_input\":\"material\",\"extra\":true}}}",
      "{\"create\":{\"target\":\"connector://table/catalog\",\"mapping\":\"mapping:table.catalog.v1\",\"from\":{\"table_input\":\"material\"}}}",
      "{\"upsert\":{\"target\":\"connector://table/catalog\",\"mapping\":\"mapping:table.catalog.v1\",\"key\":\"id\",\"set\":{},\"from\":{\"table_input\":\"material\"}}}",
    ] {
    assert_true(collect_effect_headers(table_program(effect), 1, 10) is Err(_))
  }
}
