///|
test "bounded supplied input preserves presence and shares its exact external work allowance" {
  for maximum in [52, 51] {
    let owner = presence_input_owner()
    // Nine nodes + nine name bytes = eighteen admission work. Two present
    // rows take twelve cursor polls each, the absent row ten: 34 external.
    let input = prepare_bounded_admitted_input(owner, 0, 3, {
      max_nodes: 9,
      max_text_bytes: 9,
      max_depth: 2,
      max_work: maximum,
    }).unwrap()
    let mut failed = false
    let mut polls = 0
    for row in 0..<3 {
      let cursor = start_admitted_presence_input_row(input, 3, column => {
        Some(
          if column == 0 {
            Present(@admitted.number_value((row + 1).to_double()).unwrap())
          } else if row == 0 {
            Present(@admitted.number_value(7.0).unwrap())
          } else if row == 1 {
            Present(@admitted.null_value())
          } else {
            Absent
          },
        )
      }).unwrap()
      let mut complete = false
      for _ in 0..<12 {
        if !charge_admitted_input_external_work(input, 1) {
          failed = true
          break
        }
        polls += 1
        match advance_admitted_input_row(cursor) {
          Ok(true) => {
            complete = true
            break
          }
          Ok(false) => ()
          Err(_) => {
            failed = true
            break
          }
        }
      }
      assert_true(cleanup_admitted_input_row(cursor))
      if failed {
        break
      }
      assert_true(complete)
    }
    if maximum == 52 {
      assert_false(failed)
      assert_eq(polls, 34)
      let captured = finish_admitted_input(input).unwrap()
      assert_eq(captured_usage(captured), { nodes: 9, text_bytes: 9, work: 18, })
      let live = Ref(true)
      let read = prepare_supplied_relation_read(owner, 0, captured, () => {
        live.val
      }).unwrap()
      assert_true(
        supplied_relation_read_presence_cell(read, 0, 1)
        is Some(Present(@admitted.Number(7))),
      )
      assert_true(
        supplied_relation_read_presence_cell(read, 1, 1)
        is Some(Present(@admitted.Null)),
      )
      assert_true(
        supplied_relation_read_presence_cell(read, 2, 1) is Some(Absent),
      )
      live.val = false
      assert_true(supplied_relation_read_presence_cell(read, 0, 0) is None)
    } else {
      assert_true(failed)
      assert_true(finish_admitted_input(input) is Err(ClosedCapture))
    }
    let work = admitted_input_work(input)
    let external = input.buffer.budget.external_work
    let mut reclaimed = false
    for _ in 0..<100 {
      if reclaim_admitted_input(input, 1) {
        reclaimed = true
        break
      }
    }
    assert_true(reclaimed)
    assert_true(input.buffer.rows.is_empty())
    assert_true(input.buffer.presence_rows.is_empty())
    assert_eq(admitted_input_work(input), work)
    assert_eq(input.buffer.budget.external_work, external)
    assert_true(reclaim_admitted_input(input, 1))
  }
}

///|
test "bounded supplied input refuses unavailable required and wrong typed cells before seal" {
  for invalid in 0..<3 {
    let input = prepare_bounded_admitted_input(
      presence_input_owner(),
      0,
      1,
      stream_value_limits(),
    ).unwrap()
    let cursor = start_admitted_presence_input_row(input, 3, column => {
      if column == 0 {
        match invalid {
          0 => Some(Absent)
          1 => None
          _ => Some(Present(@admitted.boolean_value(true)))
        }
      } else {
        Some(Absent)
      }
    }).unwrap()
    let mut refused = false
    for _ in 0..<12 {
      if advance_admitted_input_row(cursor) is Err(_) {
        refused = true
        break
      }
    }
    assert_true(refused)
    assert_true(finish_admitted_input(input) is Err(ClosedCapture))
    assert_true(cleanup_admitted_input_row(cursor))
    assert_true(reclaim_admitted_input(input, 64))
    assert_false(cleanup_admitted_input_row(cursor))
  }
}
