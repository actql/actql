///|
fn buffered_values_reclamation_fixture() -> (
  @bounded.Control,
  BoundedValuesExecution,
) raise {
  let rows = Array::makei(32, index => {
    "{\"id\":" + index.to_string() + ",\"n\":7}"
  }).join(",")
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"n\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows +
    "]},\"as\":\"out\"}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let values : ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 10,
    max_work: 100000,
  }
  let execution = start_bounded_values(
    control, generated, 32, values, values, 10000, 0, 1000, 10000,
  ).unwrap()
  (control, execution)
}

///|
test "bounded Values retains output reclamation custody across cleanup slices" {
  let (control, execution) = buffered_values_reclamation_fixture()
  for _ in 0..<10000 {
    if execution.state.row == 24 &&
      execution.state.phase is BuildCell &&
      execution.state.column > 0 {
      break
    }
    assert_true(
      advance_bounded_values(execution, 1).unwrap() is BoundedValuesContinue(..),
    )
  }
  assert_eq(execution.state.row, 24)
  let output = execution.state.output.unwrap()
  assert_eq(output.buffer.rows.length(), 24)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_values(execution, 1).unwrap()
    is BoundedValuesStopped(@bounded.Cancelled, ..),
  )
  assert_true(execution.state.rows.val is None)
  // Twenty-four owned rows plus forty-eight cells exceed one 64-entry slice.
  assert_false(cleanup_bounded_values(execution).unwrap())
  assert_true(bounded_values_cleanup_pending(execution))
  assert_true(execution.state.output is Some(_))
  assert_true(execution.state.workspace.live > 0)
  assert_true(output.buffer.rows.length() > 0)
  assert_eq(
    output.buffer.rows.fold(init=output.buffer.rows.length(), (count, row) => {
      count + row.length()
    }),
    8,
  )
  let work = output.buffer.budget.work
  assert_true(cleanup_bounded_values(execution).unwrap())
  assert_true(execution.state.output is None)
  assert_false(bounded_values_cleanup_pending(execution))
  assert_eq(execution.state.workspace.live, 0)
  assert_eq(output.buffer.budget.work, work)
  assert_true(output.buffer.rows.is_empty())
  assert_eq(output.buffer.rows.capacity(), 0)
  assert_false(cleanup_bounded_values(execution).unwrap())
}

///|
test "bounded output append failure keeps private rows until sliced cleanup" {
  let owner = capture_fixture()
  let output = prepare_bounded_admitted_output(owner, Step(1), 24, {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 10,
    max_work: 100000,
  }).unwrap()
  let supplied = output_fixture_row(owner, 0)
  for _ in 0..<24 {
    append_admitted_output(output, supplied).unwrap()
  }
  assert_true(append_admitted_output(output, supplied) is Err(CaptureLimit))
  assert_true(finish_admitted_output(output) is Err(ClosedCapture))
  assert_eq(output.buffer.rows.length(), 24)
  let work = output.buffer.budget.work
  assert_false(advance_admitted_output_reclamation(output))
  assert_true(output.buffer.reclaiming)
  assert_true(advance_admitted_output_reclamation(output))
  assert_eq(output.buffer.budget.work, work)
  assert_eq(output.buffer.rows.capacity(), 0)
  // Reclamation removes private containers, never the producer's values.
  assert_eq(supplied.length(), 2)
  assert_true(
    supplied[0].value is @admitted.Number(_) ||
    supplied[0].value is @admitted.Text(_),
  )
}

///|
test "sliced reclamation never mutates sealed output or presence source cells" {
  let owner = capture_fixture()
  let output = prepare_bounded_admitted_output(
    owner,
    Step(1),
    24,
    stream_value_limits(),
  ).unwrap()
  append_admitted_output(output, output_fixture_row(owner, 0)).unwrap()
  let completed_rows = finish_admitted_output(output).unwrap()
  assert_true(advance_admitted_output_reclamation(output))
  assert_eq(admitted_output_row_count(completed_rows), 1)
  assert_true(admitted_output_cell(completed_rows, 0, 0) is Some(_))
  let schema = presence_test_schema()
  let row = read_retained_relation_row(
    schema,
    "{\"id\":3}",
    retained_row_test_limits(),
    stream_value_limits(),
  ).unwrap()
  let buffer : AdmittedRowBuffer = {
    schema,
    max_rows: 24,
    budget: value_budget({
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 10,
      max_work: 100000,
    }).unwrap(),
    rows: [],
    presence_rows: [],
    open: true,
    reading: false,
    reclaiming: false,
    deferred_reclamation: true,
  }
  for _ in 0..<24 {
    append_admitted_buffer_presence(buffer, row).unwrap()
  }
  assert_false(advance_admitted_buffer_reclamation(buffer, 64))
  assert_true(buffer.reclaiming)
  assert_eq(
    buffer.presence_rows.fold(init=buffer.presence_rows.length(), (count, row) => {
      count + row.cells.length()
    }),
    8,
  )
  assert_true(advance_admitted_buffer_reclamation(buffer, 64))
  assert_eq(buffer.presence_rows.capacity(), 0)
  assert_eq(row.cells.length(), 2)
  assert_true(relation_row_cell(row, 0) is Ok(Present(@admitted.Number(3))))
  assert_true(relation_row_cell(row, 1) is Ok(Absent))
}

///|
test "failed completion retains sealed unaccepted output for sliced cleanup" {
  let (_, execution) = buffered_values_reclamation_fixture()
  for _ in 0..<10000 {
    if execution.state.phase is BeginRow && execution.state.row == 32 {
      break
    }
    assert_true(
      advance_bounded_values(execution, 1).unwrap() is BoundedValuesContinue(..),
    )
  }
  assert_true(execution.state.phase is BeginRow)
  assert_eq(execution.state.row, 32)
  let buffer = execution.state.output.unwrap().buffer
  // Revoke the real port's availability before the common completion check.
  // This is a kernel-boundary failure injection, not a public Run assertion.
  execution.state.live.val = false
  assert_true(
    advance_bounded_values(execution, 1).unwrap()
    is BoundedValuesFailed(Completion(Unverified), ..),
  )
  assert_false(execution.accepted.val)
  assert_true(execution.state.rows.val is Some(_))
  assert_false(buffer.open)
  assert_false(cleanup_bounded_values(execution).unwrap())
  assert_true(bounded_values_cleanup_pending(execution))
  assert_true(execution.state.output is Some(_))
  assert_true(cleanup_bounded_values(execution).unwrap())
  assert_false(bounded_values_cleanup_pending(execution))
  assert_true(execution.state.rows.val is None)
  assert_eq(buffer.rows.capacity(), 0)
}

///|
test "cleanup change does not imply completion after an unaccepted kernel result" {
  let (control, prepared) = buffered_values_reclamation_fixture()
  let state = prepared.state
  // Instrument only the common session's observation boundary. Preparation,
  // the production Values kernel, completion and reclamation are unchanged.
  let (session, token) = @bounded.start(
    control,
    state,
    (state, quantum, reader) => {
      let result = bounded_values_step(state, quantum, reader)
      if result is @bounded.Complete(_, _, _) {
        @bounded.request_cancel(control) |> ignore
      }
      result
    },
    cleanup_bounded_values_state,
    _ => {
      state.live.val = false
      true
    },
  )
  let active : BoundedValuesExecution = {
    state,
    session,
    token: Some(token),
    accepted: state.accepted,
  }
  let mut stopped = false
  for _ in 0..<10000 {
    match advance_bounded_values(active, 1).unwrap() {
      BoundedValuesContinue(..) => ()
      BoundedValuesStopped(@bounded.Cancelled, ..) => {
        stopped = true
        break
      }
      _ => fail("unaccepted kernel result did not stop")
    }
  }
  assert_true(stopped)
  assert_false(active.accepted.val)
  // Disposal changes the common session, but 96 entries need two slices.
  assert_true(cleanup_bounded_values(active).unwrap())
  assert_true(bounded_values_cleanup_pending(active))
  assert_true(active.state.output is Some(_))
  assert_true(cleanup_bounded_values(active).unwrap())
  assert_false(bounded_values_cleanup_pending(active))
  assert_true(active.state.output is None)
  assert_true(active.state.rows.val is None)
}
