///|
fn ordered_input_fixture(presence : Bool) -> AdmittedInput {
  let owner = if presence { presence_input_owner() } else { input_owner() }
  let input = prepare_admitted_input(owner, 0, 3, stream_value_limits()).unwrap()
  for row in 0..<3 {
    if presence {
      let wire = if row == 0 {
        "{\"id\":1,\"p\":7}"
      } else if row == 1 {
        "{\"id\":2,\"p\":null}"
      } else {
        "{\"id\":3}"
      }
      append_admitted_input_presence(
        input,
        read_retained_relation_row(
          input.buffer.schema,
          wire,
          retained_row_test_limits(),
          stream_value_limits(),
        ).unwrap(),
      ).unwrap()
    } else {
      let schema = input.buffer.schema
      let checked = Array::makei(@schema.field_count(schema), column => {
        let field = @schema.field_at(schema, column).unwrap()
        let wire = if @schema.reference_name(field.name) == "n" {
          (row + 1).to_string()
        } else {
          "\"é😀\""
        }
        @admitted.admit(field.contract, input_cursor(wire), {
          max_nodes: 10,
          max_text_bytes: 100,
          max_depth: 2,
        }).unwrap()
      })
      append_admitted_input(input, checked).unwrap()
    }
  }
  input
}

///|
test "ordered seal preserves original owner values presence and consumed work" {
  for presence in [false, true] {
    let input = ordered_input_fixture(presence)
    let schema = input.buffer.schema
    let usage = {
      nodes: input.buffer.budget.nodes,
      text_bytes: input.buffer.budget.text,
      work: input.buffer.budget.work,
    }
    let original_rows = input.buffer.rows
    let original_presence = input.buffer.presence_rows
    let captured = finish_ordered_admitted_input(input, [2, 0, 1]).unwrap()
    assert_true(physical_equal(captured_owner(captured), input.owner))
    assert_true(physical_equal(captured_schema(captured), schema))
    assert_eq(captured_origin(captured), SuppliedInput(0))
    assert_eq(captured_usage(captured), usage)
    assert_eq(captured_row_count(captured), 3)
    if presence {
      assert_true(
        physical_equal(captured.presence_rows[0], original_presence[2]),
      )
      assert_true(captured_presence_cell(captured, 0, 1) is Ok(Absent))
      assert_true(
        captured_presence_cell(captured, 1, 1)
        is Ok(Present(@admitted.Number(7))),
      )
      assert_true(
        captured_presence_cell(captured, 2, 1) is Ok(Present(@admitted.Null)),
      )
    } else {
      assert_true(physical_equal(captured.rows[0], original_rows[2]))
      assert_true(captured_cell(captured, 0, 0) is Some(@admitted.Number(3)))
      assert_true(
        captured_cell(captured, 0, 1) is Some(@admitted.Text("é😀")),
      )
    }
    assert_true(
      finish_ordered_admitted_input(input, [0, 1, 2]) is Err(ClosedCapture),
    )
    assert_false(cancel_admitted_input(input))
    assert_eq(captured_row_count(captured), 3)
  }
}

///|
test "invalid permutations leave the original input open unchanged and empty seals once" {
  for presence in [false, true] {
    let input = ordered_input_fixture(presence)
    let rows = input.buffer.rows
    let present = input.buffer.presence_rows
    for order in [[0, 0, 2], [-1, 1, 2], [0, 1, 3], [0, 1], [0, 1, 2, 3]] {
      assert_true(
        finish_ordered_admitted_input(input, order) is Err(InvalidCheckedRow),
      )
      assert_true(input.buffer.open)
      assert_true(physical_equal(input.buffer.rows, rows))
      assert_true(physical_equal(input.buffer.presence_rows, present))
    }
    let captured = finish_admitted_input(input).unwrap()
    assert_true(physical_equal(captured.rows, rows))
    assert_true(physical_equal(captured.presence_rows, present))
  }
  let empty = prepare_admitted_input(input_owner(), 0, 0, stream_value_limits()).unwrap()
  assert_eq(
    captured_row_count(finish_ordered_admitted_input(empty, []).unwrap()),
    0,
  )
  let closed = ordered_input_fixture(false)
  cancel_admitted_input(closed) |> ignore
  assert_true(
    finish_ordered_admitted_input(closed, [0, 1, 2]) is Err(ClosedCapture),
  )
}
