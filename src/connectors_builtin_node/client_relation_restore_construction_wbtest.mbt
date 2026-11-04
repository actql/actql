///|
test "borrowed full restore quote covers the actual native multiple-view export" {
  let schema = "{\"id\":{\"nullable\":false,\"type\":\"number\"},\"p\":{\"contract\":{\"max_utf8_bytes\":32,\"nullable\":true,\"type\":\"string\"},\"presence\":\"conditional\"}}"
  let cid = "sha256:326b7ad79f0904551619945e3eef1915cd61ac943ee05bb8e74f2ef61eea9ee5"
  let views : Json = {
    "views": [
      {
        "resource": "first",
        "resource_kind": "relation",
        "schema_wire": schema,
        "schema_cid": cid,
      },
      {
        "resource": "second",
        "resource_kind": "relation",
        "schema_wire": schema,
        "schema_cid": cid,
      },
    ],
  }
  let wire = views.stringify()
  let quote = client_program_relation_restore_construction_capacity(
    "restored",
    "fixture",
    "fixture/0.1",
    wire,
    ["first", "second"],
    ["relation", "relation"],
    [schema, schema],
    [None, None],
    [None, None],
    [None, None],
    [None, None],
  ).unwrap()
  let declaration = client_program_row_source_restore_relation_declaration(
    "restored",
    "fixture",
    "fixture/0.1",
    wire,
    None,
  ).unwrap()
  let exported = client_program_row_source_declaration_json(declaration)
  assert_true(exported.contains("\"first\""))
  assert_true(exported.contains("\"second\""))
  assert_true(
    @execution.execution_capacity_retained_bytes(quote) >
    exported.length().to_int64(),
  )
  assert_true(
    client_program_relation_restore_construction_capacity(
      "restored",
      "fixture",
      "fixture/0.1",
      wire,
      ["first", "second"],
      ["relation"],
      [schema, schema],
      [None, None],
      [None, None],
      [None, None],
      [None, None],
    )
    is None,
  )
}
