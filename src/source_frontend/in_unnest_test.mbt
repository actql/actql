///|
test "public SQL and Pipe routes preserve the UNNEST parameter reference" {
  let parsed = @source.parse_json(
    "{\"xs\":{\"type\":\"array\",\"max_items\":3,\"items\":{\"type\":\"number\"}}}",
    { max_input_bytes: 1024, max_nodes: 64, max_depth: 8, },
  ).unwrap()
  let cursor = @wire.admit(parsed, {
    max_nodes: 64,
    max_depth: 8,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  let declarations = @parameters.read_declarations(Some(cursor), {
    max_parameters: 10,
    max_nodes: 64,
    max_depth: 8,
    max_text_bytes: 1024,
  }).unwrap()
  let context = {
    ..test_context(),
    parameter_declarations: Some(declarations),
  }
  let cases : Array[(String, Format)] = [
    ("SELECT id FROM records WHERE id IN UNNEST((@xs))", Sql),
    ("FROM records |> WHERE id IN UNNEST(@xs) |> SELECT id", Text),
  ]
  for (text, format) in cases {
    let actual = lower(text, format, Some(context)).unwrap()
    assert_true(actual.program is Some(_))
    assert_true(
      actual.document.contains(
        "\"in\":[{\"field\":\"id\"},{\"$param\":\"xs\"}]",
      ),
    )
    assert_true(actual.document.contains("\"params\":{\"xs\":"))
  }
}
