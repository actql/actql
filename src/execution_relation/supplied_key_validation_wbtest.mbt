///|
fn supplied_key_test_input() -> SuppliedRelationRead {
  let owner = keyed_owner("[\"s\"]")
  let rows = capture_input(
    owner,
    0,
    [
      input_cursor("{\"n\":1,\"s\":\"é\"}"),
      input_cursor("{\"n\":2,\"s\":\"hello\"}"),
    ],
    max_rows=2,
    run_limits().input_values,
  ).unwrap()
  prepare_supplied_relation_read(owner, 0, rows, fn() { true }).unwrap()
}

///|
test "supplied key cursor retains exact logical work and workspace across quanta" {
  let input = supplied_key_test_input()
  let totals : Array[Int64] = []
  for quantum in [1, 7] {
    // Independent original charge: key/field 2, two schema candidates 6,
    // first row/cell/UTF-8 text 4, second row/cell/UTF-8 text 7 = 19.
    let validation = start_supplied_key_validation(
        @bounded.control(),
        input,
        19,
        100,
        5,
      )
      .unwrap()
      .unwrap()
    let mut completed = false
    let mut previous = 0L
    for _ in 0..<1000 {
      match advance_supplied_key_validation(validation, quantum).unwrap() {
        @bounded.ContinueWith(_, work~, ..) => {
          assert_true(work > previous && work - previous <= quantum.to_int64())
          previous = work
        }
        @bounded.Completed(remaining, work~, ..) => {
          assert_eq(remaining, 0)
          assert_true(work > previous && work - previous <= quantum.to_int64())
          totals.push(work)
          completed = true
          break
        }
        _ => fail("original supplied key validation did not complete")
      }
    }
    assert_true(completed)
    assert_eq(supplied_key_validation_peak_entries(validation), 5)
    assert_true(cleanup_supplied_key_validation(validation) is Ok(true))
    assert_true(cleanup_supplied_key_validation(validation) is Ok(true))
    assert_eq(validation.state.workspace.live, 0)
    assert_true(supplied_relation_read_available(input))
    assert_true(
      supplied_relation_read_cell(input, 0, 1) is Some(@admitted.Text("é")),
    )
  }
  assert_eq(totals.length(), 2)
  assert_eq(totals[0], totals[1])
}

///|
test "supplied key cursor rejects short work and workspace without leaking entries" {
  let input = supplied_key_test_input()
  for (work_limit, entry_limit) in [(18, 5), (19, 4)] {
    let validation = start_supplied_key_validation(
        @bounded.control(),
        input,
        work_limit,
        100,
        entry_limit,
      )
      .unwrap()
      .unwrap()
    let mut rejected = false
    for _ in 0..<1000 {
      match advance_supplied_key_validation(validation, 1).unwrap() {
        @bounded.ContinueWith(_, ..) => ()
        @bounded.FailedWith(Limit, ..) => {
          rejected = true
          break
        }
        _ => fail("short original key budget must reject")
      }
    }
    assert_true(rejected)
    let mut cleaned = false
    for _ in 0..<100 {
      if cleanup_supplied_key_validation(validation).unwrap() {
        cleaned = true
        break
      }
    }
    assert_true(cleaned)
    assert_eq(validation.state.workspace.live, 0)
    assert_true(
      validation.state.input is None &&
      validation.state.supplied is None &&
      validation.state.keys is None,
    )
    assert_true(supplied_relation_read_available(input))
  }
}

///|
test "supplied key cursor cancellation retires partial text and preserves borrowed rows" {
  let owner = keyed_owner("[\"s\"]")
  let rows = capture_input(
    owner,
    0,
    [input_cursor("{\"n\":1,\"s\":\"" + String::make(64, 'a') + "\"}")],
    max_rows=1,
    run_limits().input_values,
  ).unwrap()
  let input = prepare_supplied_relation_read(owner, 0, rows, fn() { true }).unwrap()
  let control = @bounded.control()
  let validation = start_supplied_key_validation(control, input, 1000, 100, 3)
    .unwrap()
    .unwrap()
  let mut reached_text = false
  for _ in 0..<1000 {
    assert_true(
      advance_supplied_key_validation(validation, 1)
      is Ok(@bounded.ContinueWith(_, ..)),
    )
    if validation.state.phase is AtomCharge &&
      validation.state.text_charge.offset > 0 {
      reached_text = true
      break
    }
  }
  assert_true(reached_text)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_supplied_key_validation(validation, 1)
    is Ok(@bounded.StoppedWith(@bounded.Cancelled, ..)),
  )
  assert_eq(validation.state.workspace.live, 2)
  assert_false(cleanup_supplied_key_validation(validation).unwrap())
  assert_true(validation.state.input is Some(_))
  let mut cleaned = false
  for _ in 0..<100 {
    if cleanup_supplied_key_validation(validation).unwrap() {
      cleaned = true
      break
    }
  }
  assert_true(cleaned)
  assert_eq(validation.state.workspace.live, 0)
  assert_true(
    validation.state.input is None &&
    validation.state.supplied is None &&
    validation.state.keys is None,
  )
  assert_true(supplied_relation_read_available(input))
  assert_eq(supplied_relation_read_row_count(input), 1)
}

///|
test "supplied key cursor rejects a narrowed unavailable input before continuing validation" {
  let input = supplied_key_test_input()
  let available = Ref(true)
  let input = restrict_supplied_relation_read(input, fn() { available.val })
  let validation = start_supplied_key_validation(
      @bounded.control(),
      input,
      19,
      100,
      5,
    )
    .unwrap()
    .unwrap()
  assert_true(
    advance_supplied_key_validation(validation, 1)
    is Ok(@bounded.ContinueWith(_, ..)),
  )
  available.val = false
  assert_true(
    advance_supplied_key_validation(validation, 1)
    is Ok(@bounded.FailedWith(WrongOrigin, ..)),
  )
  assert_true(cleanup_supplied_key_validation(validation) is Ok(true))
  assert_true(
    start_supplied_key_validation(@bounded.control(), input, 19, 100, 5)
    is Err(WrongOrigin),
  )
}
