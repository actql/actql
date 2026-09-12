///|
test "owned occurrence buffers compose with bounded overlap and survive projection" {
  let schema = capture_values(
      row_owner(""),
      0,
      max_rows=2,
      run_limits().input_values,
    ).unwrap().schema
  let ledger = layout_ledger(7, 36, 100)
  let budget = {
    ..layout_allocation(10000, 10000, 10000),
    ledger: Some(ledger),
  }
  let builder = layout_column_builder(
    schema,
    ["a", "b"],
    2,
    TypedColumns,
    budget,
  ).unwrap()
  append_layout_row(builder, [Number(1), Number(2)]).unwrap()
  append_layout_row(builder, [Number(3), Number(4)]).unwrap()
  let source = finish_layout_columns(builder).unwrap()
  let view = select_layout_rows(source, [1, 0, 1], budget).unwrap()
  let projected = project_layout(view, [0], budget).unwrap()
  // Projection shares the occurrence buffer, not a second charged copy.
  assert_eq(ledger.slots.live, 5)
  let composed = select_layout_rows(projected, [2, 1], budget).unwrap()
  assert_eq(ledger.slots.live, 7)
  assert_true(layout_cell(composed, 0, 0) is Some(Number(3)))
  assert_true(layout_cell(composed, 1, 0) is Some(Number(1)))
  assert_true(select_layout_rows(projected, [0], budget) is Err(Limit))
  assert_eq(ledger.slots.live, 7)
  release_layout_columns(source)
  release_layout_columns(view)
  assert_eq(ledger.slots.live, 6)
  release_layout_columns(projected)
  assert_eq(ledger.slots.live, 3)
  assert_eq(ledger.bytes.live, 18)
  assert_true(layout_cell(projected, 0, 0) is None)
  assert_true(layout_cell(composed, 0, 0) is Some(Number(3)))
  // A failed share rolls back the freshly allocated selection buffer.
  ledger.work.remaining = 1
  assert_true(select_layout_rows(composed, [0], budget) is Err(Limit))
  assert_eq(ledger.slots.live, 3)
  release_layout_columns(composed)
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  assert_eq(ledger.slots.peak, 7)
  assert_eq(ledger.work.remaining, 0)
}

///|
fn share_layout_columns(
  columns : Array[LayoutOwnedBuffer[LayoutColumn]],
  ordinals : Array[Int],
  budget : LayoutAllocation,
) -> Result[Array[LayoutOwnedBuffer[LayoutColumn]], LayoutStorageIssue] {
  guard budget.ledger is Some(ledger) else { return Err(Shape) }
  let result : Array[LayoutOwnedBuffer[LayoutColumn]] = []
  for ordinal in ordinals {
    if ordinal < 0 || ordinal >= columns.length() {
      for handle in result {
        ignore(release_owned_layout_buffer(ledger, handle))
      }
      return Err(Shape)
    }
    match share_owned_layout_buffer(ledger, columns[ordinal]) {
      Ok(handle) => result.push(handle)
      Err(issue) => {
        for handle in result {
          ignore(release_owned_layout_buffer(ledger, handle))
        }
        return Err(issue)
      }
    }
  }
  Ok(result)
}

///|
fn release_layout_columns(storage : LayoutStorage) -> Unit {
  if storage.owned_selection is Some(handle) {
    ignore(release_owned_layout_buffer(handle.lease.buffer.ledger, handle))
  }
  if storage.body is OwnedColumnArrays(columns) {
    for handle in columns {
      ignore(release_owned_layout_buffer(handle.lease.buffer.ledger, handle))
    }
  }
}

///|
test "owned column projections release only columns with no surviving view" {
  let owner = row_owner("")
  let schema = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap().schema
  let ledger = layout_ledger(3, 36, 100)
  let budget = {
    ..layout_allocation(10000, 10000, 10000),
    ledger: Some(ledger),
  }
  let builder = layout_column_builder(
    schema,
    ["a", "b"],
    2,
    TypedColumns,
    budget,
  ).unwrap()
  append_layout_row(builder, [Number(1), Number(2)]).unwrap()
  append_layout_row(builder, [Number(3), Number(4)]).unwrap()
  let source = finish_layout_columns(builder).unwrap()
  assert_true(
    append_layout_row(builder, [Number(9), Number(9)]) is Err(InvalidRows),
  )
  assert_true(layout_cell(source, 0, 0) is Some(Number(1)))
  assert_eq(builder.columns.length(), 0)
  let projected = project_layout(source, [1], budget).unwrap()
  let selected = select_layout_rows(projected, [1], budget).unwrap()
  assert_eq(ledger.bytes.live, 36)
  release_layout_columns(source)
  assert_true(layout_cell(source, 0, 0) is None)
  assert_eq(ledger.bytes.live, 18)
  release_layout_columns(projected)
  assert_eq(ledger.bytes.live, 18)
  assert_true(layout_cell(selected, 0, 0) is Some(Number(4)))
  release_layout_columns(selected)
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  assert_eq(ledger.bytes.peak, 36)
}

///|
test "owned column failed construction and failed sharing release only new resources" {
  let schema = capture_values(
      row_owner(""),
      0,
      max_rows=2,
      run_limits().input_values,
    ).unwrap().schema
  let ledger = layout_ledger(2, 35, 100)
  let budget = {
    ..layout_allocation(10000, 10000, 10000),
    ledger: Some(ledger),
  }
  assert_true(
    layout_column_builder(schema, ["a", "b"], 2, TypedColumns, budget)
    is Err(RowLimit),
  )
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  let ledger = layout_ledger(2, 36, 100)
  let budget = {
    ..layout_allocation(10000, 10000, 10000),
    ledger: Some(ledger),
  }
  let builder = layout_column_builder(
    schema,
    ["a", "b"],
    2,
    TypedColumns,
    budget,
  ).unwrap()
  assert_true(
    append_layout_row(builder, [Number(1), Boolean(true)]) is Err(InvalidRows),
  )
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
  let builder = layout_column_builder(
    schema,
    ["a", "b"],
    2,
    TypedColumns,
    budget,
  ).unwrap()
  append_layout_row(builder, [Number(1), Number(2)]).unwrap()
  let source = finish_layout_columns(builder).unwrap()
  ledger.work.remaining = 1
  assert_true(project_layout(source, [0, 1], budget) is Err(Limit))
  assert_eq((ledger.slots.live, ledger.bytes.live), (2, 36))
  assert_true(layout_cell(source, 0, 1) is Some(Number(2)))
  release_layout_columns(source)
  assert_eq((ledger.slots.live, ledger.bytes.live), (0, 0))
}
