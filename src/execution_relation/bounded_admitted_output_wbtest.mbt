///|
fn stepped_output_fixture(
  values : ValueLimits,
  work : Int,
  workspace : Int,
) -> (AdmittedOutput, AdmittedOutputPreparation) {
  let owner = capture_fixture()
  let output = prepare_admitted_output(owner, Step(1), 2, values).unwrap()
  let cells = [output_fixture_row(owner, 0), output_fixture_row(owner, 1)]
  let active = start_admitted_output_preparation(output, 2, work, workspace, (
    row,
    col,
  ) => cells[row].get(col).map(value => value.value)).unwrap()
  (output, active)
}

///|
test "bounded output import transfers accepted rows once without cleanup erasing them" {
  let (_, active) = stepped_output_fixture(
    { max_nodes: 6, max_text_bytes: 10, max_depth: 2, max_work: 16, },
    26,
    7,
  )
  assert_true(take_admitted_output_preparation_rows(active) is None)
  let mut complete = false
  for _ in 0..<26 {
    match advance_admitted_output_preparation(active, 1).unwrap() {
      AdmittedOutputContinue(..) => ()
      AdmittedOutputComplete(_, ..) => {
        complete = true
        break
      }
      _ => fail("row handoff import failed")
    }
  }
  assert_true(complete)
  let rows = take_admitted_output_preparation_rows(active).unwrap()
  assert_eq(rows.rows.length(), 2)
  assert_eq(active.state.workspace.live, 0)
  assert_true(take_admitted_output_preparation_rows(active) is None)
  assert_true(admitted_output_preparation_rows(active) is None)
  assert_true(cleanup_admitted_output_preparation(active).unwrap())
  assert_eq(rows.rows.length(), 2)
  assert_eq(admitted_output_usage(rows), { nodes: 6, text_bytes: 10, work: 16, })
}

///|
test "bounded output import preserves exact logical charges and admits cells incrementally" {
  let limits : ValueLimits = {
    max_nodes: 6,
    max_text_bytes: 10,
    max_depth: 2,
    max_work: 16,
  }
  // Each row has a number and Text: Begin + (Read + Node + Complete + Name
  // + Value) + (Read + Node + TextUnits + Complete + Name + Value) + Commit.
  // The two short Text values, "é" and "😀", each need one TextUnits poll.
  // Two 13-step rows plus terminal Begin + Seal cost 28 physical work units;
  // logical usage remains six nodes, ten text bytes and sixteen work units.
  // Row storage is six slots, plus one measurement frame.
  let (output, active) = stepped_output_fixture(limits, 28, 7)
  assert_true(admitted_output_preparation_rows(active) is None)
  assert_true(finish_admitted_output(output) is Err(ClosedCapture))
  let mut total = 0L
  let mut material : AdmittedOutputRows? = None
  for _ in 0..<28 {
    match advance_admitted_output_preparation(active, 1).unwrap() {
      AdmittedOutputContinue(work~) => {
        assert_eq(work - total, 1L)
        total = work
      }
      AdmittedOutputComplete(rows, work~) => {
        assert_eq(work - total, 1L)
        total = work
        material = Some(rows)
        break
      }
      _ => fail("bounded import did not complete")
    }
  }
  assert_eq(total, 28L)
  let rows = material.unwrap()
  assert_eq(admitted_output_row_count(rows), 2)
  assert_eq(admitted_output_usage(rows), { nodes: 6, text_bytes: 10, work: 16, })
  assert_true(
    physical_equal(admitted_output_preparation_rows(active).unwrap(), rows),
  )
  assert_true(cleanup_admitted_output_preparation(active).unwrap())
  assert_eq(active.state.workspace.live, 0)
  assert_true(cleanup_admitted_output_preparation(active).unwrap())
  assert_true(admitted_output_preparation_rows(active) is None)
  assert_true(rows.rows.is_empty())
}

///|
test "bounded output import rejects independent one-short limits and retains cleanup" {
  let limits : ValueLimits = {
    max_nodes: 6,
    max_text_bytes: 10,
    max_depth: 2,
    max_work: 16,
  }
  for
    (values, work, workspace) in [
      (limits, 27, 7),
      (limits, 28, 6),
      ({ ..limits, max_work: 15, }, 28, 7),
      ({ ..limits, max_nodes: 5, }, 28, 7),
      ({ ..limits, max_text_bytes: 9, }, 28, 7),
    ] {
    let (_, active) = stepped_output_fixture(values, work, workspace)
    let mut rejected = false
    for _ in 0..<30 {
      match advance_admitted_output_preparation(active, 1).unwrap() {
        AdmittedOutputContinue(..) => ()
        AdmittedOutputFailed(CaptureLimit | InvalidCheckedRow, ..) => {
          rejected = true
          break
        }
        _ => fail("one-short output import unexpectedly completed")
      }
    }
    assert_true(rejected)
    assert_true(admitted_output_preparation_rows(active) is None)
    assert_true(cleanup_admitted_output_preparation(active).unwrap())
    assert_eq(active.state.workspace.live, 0)
    assert_true(active.state.output.buffer.rows.is_empty())
  }
}

///|
test "bounded output import cancellation does not seal pending material or read again" {
  let limits : ValueLimits = {
    max_nodes: 6,
    max_text_bytes: 10,
    max_depth: 2,
    max_work: 16,
  }
  let (_, active) = stepped_output_fixture(limits, 28, 7)
  assert_true(
    advance_admitted_output_preparation(active, 1).unwrap()
    is AdmittedOutputContinue(work=1L),
  )
  assert_true(cancel_admitted_output_preparation(active))
  assert_true(
    advance_admitted_output_preparation(active, 1).unwrap()
    is AdmittedOutputStopped(work=1L),
  )
  assert_true(admitted_output_preparation_rows(active) is None)
  assert_true(cleanup_admitted_output_preparation(active).unwrap())
  assert_eq(active.state.workspace.live, 0)
}

///|
test "bounded output import can stop during nested admission before measurement or sealing" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":[]},\"as\":\"input\"},{\"select\":[\"items\"]}]",
  )
  let output = prepare_admitted_output(owner, Step(1), 1, {
    max_nodes: 4100,
    max_text_bytes: 5,
    max_depth: 3,
    max_work: 5000,
  }).unwrap()
  let values = @admitted.array_value(
    Array::make(4096, @admitted.number_value(1.0).unwrap()),
  )
  let mut reads = 0
  let active = start_admitted_output_preparation(output, 1, 20000, 6, (_, _) => {
    reads += 1
    Some(values)
  }).unwrap()
  for _ in 0..<20 {
    assert_true(
      advance_admitted_output_preparation(active, 1).unwrap()
      is AdmittedOutputContinue(..),
    )
  }
  assert_eq(reads, 1)
  assert_true(active.state.admission is Some(_))
  assert_true(active.state.output.buffer.rows.is_empty())
  assert_true(cancel_admitted_output_preparation(active))
  assert_true(
    advance_admitted_output_preparation(active, 1).unwrap()
    is AdmittedOutputStopped(work=20L),
  )
  assert_true(cleanup_admitted_output_preparation(active).unwrap())
  assert_eq(reads, 1)
  assert_eq(active.state.workspace.live, 0)
  assert_true(active.state.admission is None)
}
