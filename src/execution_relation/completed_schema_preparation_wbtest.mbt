///|
test "publication metadata polls recursive schema before stream transfer and cancellation" {
  let fields = StringBuilder()
  let row = StringBuilder()
  for index in 0..<65 {
    if index > 0 {
      fields.write_string(",")
      row.write_string(",")
    }
    let name = "k" + (1000 + index).to_string()
    fields.write_string(
      "\"" + name + "\":{\"type\":\"number\",\"nullable\":false}",
    )
    row.write_string("\"" + name + "\":1")
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"object\",\"nullable\":false,\"fields\":{" +
    fields.to_string() +
    "}}},\"rows\":[{\"payload\":{" +
    row.to_string() +
    "}}]},\"as\":\"v\"},{\"select\":[\"payload\"]}]",
  )
  for cancel in [false, true] {
    let source = export_fixture(owner)
    let schema = @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      source.target,
    ).unwrap()
    let cursor = start_completed_export_rows_metadata(
      source,
      {
        table: source.table.unwrap(),
        schema,
        names: ["payload"],
        columns: None,
        rows: None,
      },
      1,
      stream_value_limits(),
      row_wire_limits(),
      Some(row_wire_limits()),
      Some({ max_fields: 1, max_bytes: 4000, max_nodes: 201, max_depth: 4, }),
      64,
      24,
    ).unwrap()
    let mut found = false
    for _ in 0..<10000 {
      let (done, used) = advance_completed_output_export_preparation(cursor, 1).unwrap()
      assert_eq(used, 1)
      if cursor.schema_cursor is Some(preparation) && preparation.phase == 4 {
        found = true
        assert_true(cursor.stream is None)
        if cancel {
          assert_true(cancel_completed_output_export_preparation(cursor))
          assert_false(cancel_completed_output_export_preparation(cursor))
          assert_true(preparation.closed && preparation.schema is None)
          break
        }
      }
      if done {
        break
      }
    }
    assert_true(found)
    if cancel {
      assert_true(
        cursor.schema_cursor is None && cursor.schema_identity is None,
      )
      assert_true(cursor.stream is None && cursor.rows is None)
      assert_eq(cursor.workspace.live, 0)
    } else {
      let stream = finish_completed_output_export_preparation(cursor).unwrap()
      assert_true(stream.schema is Some(_))
      assert_true(
        cursor.schema_identity is None && cursor.schema_cursor is None,
      )
      assert_eq(cursor.workspace.live, 0)
      cancel_completed_output_export(stream)
    }
    assert_true(completed_output_available(source))
  }
}
