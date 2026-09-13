///|
test "output cell readers cannot seal reentrantly or append after cancellation" {
  let owner = capture_fixture()
  let limits : ValueLimits = {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 3,
    max_work: 1000,
  }
  let row = output_fixture_row(owner, 0)
  let output = prepare_admitted_output(owner, Step(1), 2, limits).unwrap()
  let mut sealed_early = false
  let mut appended_early = false
  append_admitted_output_cells(output, 2, column => {
    sealed_early = finish_admitted_output(output) is Ok(_)
    appended_early = append_admitted_output(output, row) is Ok(_)
    row.get(column)
  }).unwrap()
  assert_false(sealed_early)
  assert_false(appended_early)
  assert_eq(
    admitted_output_row_count(finish_admitted_output(output).unwrap()),
    1,
  )
  let cancelled = prepare_admitted_output(owner, Step(1), 2, limits).unwrap()
  assert_true(
    append_admitted_output_cells(cancelled, 2, column => {
      cancel_admitted_output(cancelled) |> ignore
      row.get(column)
    })
    is Err(ClosedCapture),
  )
  assert_true(cancelled.buffer.rows.is_empty())
  assert_true(finish_admitted_output(cancelled) is Err(ClosedCapture))
}

///|
fn output_fixture_row(
  owner : @lower.BoundPrepared,
  row : Int,
) -> Array[@admitted.CheckedValue] {
  let schema = @pipeline.schema_at(
    @lower.pipeline(@lower.bound_preparation(owner)),
    Step(1),
  ).unwrap()
  Array::makei(@schema.field_count(schema), column => {
    let field = @schema.field_at(schema, column).unwrap()
    let text = if @schema.reference_name(field.name) == "n" {
      (row + 1).to_string()
    } else if row == 0 {
      "\"é\""
    } else {
      "\"😀\""
    }
    @admitted.admit(field.contract, input_cursor(text), {
      max_nodes: 10,
      max_text_bytes: 100,
      max_depth: 2,
    }).unwrap()
  })
}

///|
test "provisional output retains exact checked target and shared immutable values without granting completion" {
  let owner = capture_fixture()
  let limits : ValueLimits = {
    max_nodes: 6,
    max_text_bytes: 10,
    max_depth: 2,
    max_work: 16,
  }
  let output = prepare_admitted_output(owner, Step(1), 2, limits).unwrap()
  let row = output_fixture_row(owner, 0)
  append_admitted_output(output, row).unwrap()
  row.clear()
  append_admitted_output(output, output_fixture_row(owner, 1)).unwrap()
  let retained = finish_admitted_output(output).unwrap()
  assert_true(physical_equal(admitted_output_owner(retained), owner))
  assert_eq(admitted_output_target(retained), Step(1))
  assert_eq(admitted_output_row_count(retained), 2)
  assert_eq(admitted_output_usage(retained), {
    nodes: 6,
    text_bytes: 10,
    work: 16,
  })
  for col in 0..<2 {
    let name = @schema.reference_name(
      @schema.field_at(admitted_output_schema(retained), col).unwrap().name,
    )
    if name == "n" {
      assert_true(
        admitted_output_cell(retained, 1, col) is Some(@admitted.Number(2.0)),
      )
    } else {
      assert_true(
        admitted_output_cell(retained, 1, col) is Some(@admitted.Text("😀")),
      )
    }
  }
  assert_true(admitted_output_cell(retained, -1, 0) is None)
  assert_true(admitted_output_cell(retained, 0, 2) is None)
  assert_false(cancel_admitted_output(output))
  assert_true(finish_admitted_output(output) is Err(ClosedCapture))
  assert_true(append_admitted_output(output, []) is Err(ClosedCapture))
}

///|
test "provisional output rejection is atomic under exact ownership and resource bounds" {
  let owner = capture_fixture()
  let limits : ValueLimits = {
    max_nodes: 6,
    max_text_bytes: 10,
    max_depth: 2,
    max_work: 16,
  }
  for target in [@pipeline.Input(0), Step(-1), Step(2)] {
    assert_true(
      prepare_admitted_output(owner, target, 2, limits)
      is Err(NotRelationOutput),
    )
  }
  let foreign = prepare_admitted_output(owner, Step(1), 2, limits).unwrap()
  assert_true(
    append_admitted_output(foreign, output_fixture_row(capture_fixture(), 0))
    is Err(ForeignCheckedValue(0, 0)),
  )
  assert_true(finish_admitted_output(foreign) is Err(ClosedCapture))
  for
    bound in [
      { ..limits, max_nodes: 5, },
      { ..limits, max_text_bytes: 9, },
      { ..limits, max_work: 15, },
      { ..limits, max_depth: 1, },
    ] {
    let output = prepare_admitted_output(owner, Step(1), 2, bound).unwrap()
    let first = append_admitted_output(output, output_fixture_row(owner, 0))
    if first is Ok(_) {
      assert_true(
        append_admitted_output(output, output_fixture_row(owner, 1))
        is Err(CaptureLimit),
      )
    } else {
      assert_true(first is Err(CaptureLimit))
    }
    assert_true(finish_admitted_output(output) is Err(ClosedCapture))
    assert_true(output.buffer.rows.is_empty())
  }
  let cancelled = prepare_admitted_output(owner, Step(1), 2, limits).unwrap()
  append_admitted_output(cancelled, output_fixture_row(owner, 0)).unwrap()
  assert_true(cancel_admitted_output(cancelled))
  assert_true(cancelled.buffer.rows.is_empty())
  assert_true(finish_admitted_output(cancelled) is Err(ClosedCapture))
  let no_capacity = prepare_admitted_output(owner, Step(1), 0, limits).unwrap()
  let mut reads = 0
  assert_true(
    append_admitted_output_cells(no_capacity, 2, _ => {
      reads += 1
      None
    })
    is Err(CaptureLimit),
  )
  assert_eq(reads, 0)
}
