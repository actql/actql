///|
test "scalar name capacity charges UTF8 names per admitted row at exact and one-short boundaries" {
  for width in [1, 2, 4] {
    let fields = []
    for index in 0..<width {
      fields.push(
        (
          @schema.Unqualified("列" + index.to_string()),
          @contract.primitive(NumberType, nullable=true),
        ),
      )
    }
    let schema = @schema.from_fields(
      fields,
      max_fields=100,
      max_name_bytes=1000,
    ).unwrap()
    let names = @schema.field_reference_name_bytes(schema)
    assert_eq(names, 4 * width)
    for rows in [0, 1, 25, 26, 49, 50, 51, 99, 100] {
      let exact = names * rows
      for ceiling in [exact, if exact == 0 { 0 } else { exact - 1 }] {
        let budget = value_budget({
          max_nodes: (width + 1) * rows,
          max_text_bytes: ceiling,
          max_depth: 10,
          max_work: 100000,
        }).unwrap()
        let input : AdmittedRowBuffer = {
          schema,
          max_rows: rows,
          budget,
          rows: [],
          presence_rows: [],
          open: true,
          reading: false,
          reclaiming: false,
          deferred_reclamation: false,
        }
        let mut accepted = true
        for _ in 0..<rows {
          if append_admitted_buffer_values(
              input,
              schema,
              Array::make(width, @admitted.null_value()),
            )
            is Err(_) {
            accepted = false
            break
          }
        }
        assert_eq(accepted, ceiling == exact)
        if accepted {
          assert_eq(budget.text, exact)
        }
        cancel_admitted_buffer(input) |> ignore
        assert_true(input.rows.is_empty())
      }
    }
  }
}
