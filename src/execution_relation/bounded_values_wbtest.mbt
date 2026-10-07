///|
fn bounded_values_fixture(
  max_work? : Int = 15,
  max_entries? : Int = 4,
  name_bytes? : Int = 100,
  label_name? : String = "label",
) -> (@bounded.Control, Result[BoundedValuesExecution, BoundedValuesIssue]) raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"" +
    label_name +
    "\":{\"type\":\"string\",\"nullable\":false}}," +
    "\"rows\":[{\"id\":1,\"" +
    label_name +
    "\":\"one\"}," +
    "{\"id\":2,\"" +
    label_name +
    "\":\"two\"}]},\"as\":\"out\"}]",
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
  let active = start_bounded_values(
    control,
    generated,
    2,
    run_limits().input_values,
    run_limits().output_values,
    max_work,
    0,
    max_entries,
    name_bytes,
  )
  (control, active)
}

///|
test "bounded values build checked zero-input rows within quantum" {
  let (_, started) = bounded_values_fixture()
  let active = started.unwrap()
  let mut last_work = 0L
  let mut completed = false
  let mut advances = 0
  while !completed && advances < 100 {
    advances += 1
    match advance_bounded_values(active, 1).unwrap() {
      BoundedValuesContinue(work~, ..) => {
        assert_true(work - last_work <= 1L)
        last_work = work
      }
      BoundedValuesComplete(output, work~, ..) => {
        assert_true(work - last_work <= 1L)
        assert_eq(completed_row_count(output), 2)
        assert_true(completed_cell(output, 0, 0) is Some(Number(1.0)))
        assert_true(completed_cell(output, 1, 1) is Some(Text("two")))
        completed = true
      }
      BoundedValuesFailed(_, ..) => fail("bounded values failed")
      BoundedValuesStopped(_, ..) => fail("bounded values stopped")
    }
  }
  assert_true(completed)
  assert_true(advances > 5)
  assert_true(cleanup_bounded_values(active).unwrap())
}

///|
test "bounded values reject one-short work and workspace" {
  let (_, work_started) = bounded_values_fixture(max_work=14)
  let work_short = work_started.unwrap()
  let mut failed = false
  for _ in 0..<100 {
    match advance_bounded_values(work_short, 1).unwrap() {
      BoundedValuesContinue(_) => ()
      BoundedValuesFailed(Rows(RowLimit), ..) => {
        failed = true
        break
      }
      _ => fail("one-short work had an unexpected result")
    }
  }
  assert_true(failed)
  assert_true(cleanup_bounded_values(work_short).unwrap())

  let (_, workspace_short) = bounded_values_fixture(max_entries=3)
  assert_true(workspace_short is Err(InputLimit))
}

///|
test "bounded values stop after cell work without publishing" {
  let (control, started) = bounded_values_fixture()
  let active = started.unwrap()
  // Reach the same cell boundary after resumable completion admission.
  let mut reached = false
  for _ in 0..<1000 {
    if active.state.phase is BuildCell && active.state.column > 0 {
      reached = true
      break
    }
    assert_true(
      advance_bounded_values(active, 1) is Ok(BoundedValuesContinue(..)),
    )
  }
  assert_true(reached)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_values(active, 1)
    is Ok(BoundedValuesStopped(@bounded.Cancelled, ..)),
  )
  assert_true(cleanup_bounded_values(active).unwrap())
}
