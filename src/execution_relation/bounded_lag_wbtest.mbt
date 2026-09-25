///|
fn bounded_lag_fixture(
  max_work? : Int = 100000,
  max_entries? : Int = 10000,
) -> (@bounded.Control, BoundedBindingRowsExecution) raise {
  let owner = lag_input_owner("1")
  let rows = lag_rows()
  let captured = capture_input(
    owner,
    0,
    rows,
    max_rows=rows.length(),
    run_limits().input_values,
  ).unwrap()
  let read = prepare_supplied_relation_read(owner, 0, captured, fn() { true }).unwrap()
  let sequence = prepared_sequence(owner)
  let node = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [@lower.node_id(node)],
    100000,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let active = start_bounded_binding_rows_supplied(
    control,
    generated,
    read,
    rows.length(),
    run_limits().input_values,
    run_limits().output_values,
    max_work,
    100,
    max_entries,
    10000,
  ).unwrap()
  (control, active)
}

///|
test "bounded lag preserves partitions and occurrence order at quantum one" {
  let (_, active) = bounded_lag_fixture()
  let mut result : CompletedOutput? = None
  let mut polls = 0
  let mut prior_work = 0L
  while result is None && polls < 10000 {
    polls += 1
    match advance_bounded_binding_rows(active, 1).unwrap() {
      BoundedBindingRowsContinue(work~, ..) => {
        assert_true(work - prior_work <= 1L)
        prior_work = work
      }
      BoundedBindingRowsComplete(output, work~, ..) => {
        assert_true(work - prior_work <= 1L)
        result = Some(output)
      }
      _ => fail("bounded lag did not complete")
    }
  }
  guard result is Some(output) else { fail("bounded lag did not finish") }
  assert_true(polls > 5)
  assert_eq(completed_row_count(output), 5)
  assert_true(completed_cell(output, 0, 3) is Some(Null))
  assert_true(completed_cell(output, 1, 3) is Some(Null))
  assert_true(completed_cell(output, 2, 3) is Some(Number(30.0)))
  assert_true(completed_cell(output, 3, 3) is Some(Number(20.0)))
  assert_true(completed_cell(output, 4, 3) is Some(Number(30.0)))
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
}

///|
test "bounded lag stops and reclaims before publishing rows" {
  let (control, active) = bounded_lag_fixture()
  for _ in 0..<12 {
    assert_true(
      advance_bounded_binding_rows(active, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(active, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_true(bounded_binding_rows_cleanup_pending(active))
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
}

///|
test "bounded lag admits its exact structural workspace peak" {
  // Sixteen metadata slots overlap two normalized sort terms, five lag
  // values, and two four-cell row buffers at the commit frontier.
  for (space, accepted) in [(31, true), (30, false)] {
    let (_, active) = bounded_lag_fixture(max_entries=space)
    let mut finished = false
    for _ in 0..<10000 {
      match advance_bounded_binding_rows(active, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(_, ..) => {
          finished = true
          break
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => break
        _ => fail("bounded lag workspace failed unexpectedly")
      }
    }
    assert_eq(finished, accepted)
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
  }
}
