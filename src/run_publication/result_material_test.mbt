///|
test "Result material rechecks original contracts and preserves signed64 presentation" {
  let schema = prepare_result_material_schema(
    "{\"id\":{\"type\":\"integer\",\"nullable\":false},\"name\":{\"type\":\"string\",\"nullable\":false},\"large\":{\"type\":\"signed64\",\"nullable\":false}}",
    ["id", "name", "large"],
    4096,
    256,
    16,
    8,
  ).unwrap()
  let row = admit_result_material_row(
    schema, "{\"large\":\"9223372036854775807\",\"name\":\"hello\",\"id\":1}",
  ).unwrap()
  assert_eq(
    render_result_material_table(schema, [row], 1, 4096),
    Ok(
      "id  name   large\n--  -----  -------------------\n1   hello  9223372036854775807\n",
    ),
  )
  for
    wire in [
      "{\"id\":\"1\",\"name\":\"hello\",\"large\":\"1\"}", "{\"id\":1,\"name\":\"hello\",\"large\":9223372036854775807}",
      "{\"id\":1,\"name\":\"hello\",\"large\":\"9223372036854775808\"}", "{\"id\":1,\"name\":\"hello\",\"large\":\"01\"}",
    ] {
    assert_true(
      admit_result_material_row(schema, wire) is Err(MaterialTypeMismatch),
    )
  }
}

///|
test "Result material table bounds foreign rows exact fields and terminal controls" {
  let wire = "{\"v\":{\"type\":\"string\",\"nullable\":false}}"
  let schema = prepare_result_material_schema(wire, ["v"], 4096, 256, 16, 8).unwrap()
  let other = prepare_result_material_schema(wire, ["v"], 4096, 256, 16, 8).unwrap()
  let row = admit_result_material_row(schema, "{\"v\":\"é\\n\\u001b\"}").unwrap()
  assert_eq(
    render_result_material_table(other, [row], 1, 4096),
    Err(MaterialForeignSchema),
  )
  assert_true(
    admit_result_material_row(schema, "{\"v\":\"a\",\"extra\":0}")
    is Err(MaterialInvalidRow),
  )
  assert_true(
    admit_result_material_row(schema, "{}") is Err(MaterialInvalidRow),
  )
  assert_eq(
    render_result_material_table(schema, [row], 0, 4096),
    Err(MaterialInvalidLimits),
  )
  assert_eq(
    render_result_material_table(schema, [row], 1, 4),
    Err(MaterialOutputLimit),
  )
  let table = render_result_material_table(schema, [row], 1, 4096).unwrap()
  assert_true(table.contains("e\\u{301}\\u{a}\\u{1b}"))
  assert_false(table.contains("\u{1b}"))
}
