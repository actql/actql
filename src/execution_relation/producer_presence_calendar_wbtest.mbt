///|
test "Calendar producer projection distinguishes value NULL absence and unavailable" {
  let (owner, execution, _) = presence_selection_fixture()
  let source = presence_filter_complete(execution)
  let receiver = typed_receiver(owner, "[]", target=Step(0))
  let live = Ref(true)
  let selected = restrict_completed_output(source, () => live.val)
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, selected).unwrap(),
    100,
    10000,
  ).unwrap()
  for row in 0..<4 {
    assert_eq(producer_read_cell_present(read, row, 0), Ok(true))
    assert_eq(producer_read_cell_present(read, row, 1), Ok(row != 1))
    if row == 1 {
      assert_true(
        start_producer_read_cell_recheck(read, row, 1, {
          max_nodes: 10,
          max_text_bytes: 100,
          max_depth: 10,
        })
        is None,
      )
    } else {
      let cursor = start_producer_read_cell_recheck(read, row, 1, {
        max_nodes: 10,
        max_text_bytes: 100,
        max_depth: 10,
      }).unwrap()
      let mut checked = None
      for _ in 0..<10 {
        if checked is None {
          match @admitted.advance_recheck_runtime_value(cursor) {
            RecheckContinue => ()
            RecheckComplete(value, _, _) => checked = Some(value)
            RecheckFailed =>
              fail("original conditional present cell must recheck")
          }
        }
      }
      let value = checked.unwrap().value
      if row == 2 {
        assert_true(value is @admitted.Null)
      } else {
        assert_true(
          value is @admitted.Number(number) &&
          number == (if row == 0 { 8.0 } else { 7.0 }),
        )
      }
    }
  }
  assert_eq(producer_read_cell_present(read, 4, 0), Err(InvalidLayout))
  assert_eq(producer_read_cell_present(read, 0, 2), Err(InvalidLayout))
  live.val = false
  assert_eq(producer_read_cell_present(read, 0, 0), Err(Unavailable))
  assert_true(
    start_producer_read_cell_recheck(read, 0, 0, {
      max_nodes: 10,
      max_text_bytes: 100,
      max_depth: 10,
    })
    is None,
  )
}
