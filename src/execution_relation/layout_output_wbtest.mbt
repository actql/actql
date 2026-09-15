///|
// Mutable construction is invocation-local; finish seals it before publication.
priv struct LayoutColumnBuilder {
  columns : Array[LayoutColumn]
  owned : Array[LayoutOwnedBuffer[LayoutColumn]]?
  capacity : Int
  mut count : Int
  mut closed : Bool
  budget : LayoutAllocation
}

///|
fn layout_column_builder(
  schema : @schema.Schema,
  names : Array[String],
  capacity : Int,
  candidate : LayoutCandidate,
  budget : LayoutAllocation,
) -> Result[LayoutColumnBuilder, RowIssue] {
  if capacity < 0 ||
    names.length() != @schema.field_count(schema) ||
    candidate == RowLayout {
    return Err(InvalidRows)
  }
  if !reserve_slots(budget.slots, names.length()) ||
    !spend_control(budget.work, names.length()) {
    return Err(RowLimit)
  }
  let contracts : Array[@contract.Contract] = []
  if !reserve_slots(budget.slots, names.length()) {
    return Err(RowLimit)
  }
  for name in names {
    if !spend_control_text(budget.work, name) {
      return Err(RowLimit)
    }
    guard @schema.lookup_reference(schema, name) is Some(field) else {
      return Err(InvalidRows)
    }
    contracts.push(field.contract)
    if candidate == TypedColumns && field.contract.shape is @contract.Number {
      if !layout_bytes(budget, capacity, 8) ||
        !layout_bytes(budget, capacity, 1) {
        return Err(RowLimit)
      }
    } else if candidate == TypedColumns &&
      field.contract.shape is @contract.Boolean {
      if !layout_bytes(budget, capacity, 1) ||
        !layout_bytes(budget, capacity, 1) {
        return Err(RowLimit)
      }
    } else if !reserve_slots(budget.slots, capacity) {
      return Err(RowLimit)
    }
  }
  let columns : Array[LayoutColumn] = []
  let owned : Array[LayoutOwnedBuffer[LayoutColumn]] = []
  for contract in contracts {
    let numeric = candidate == TypedColumns &&
      contract.shape is @contract.Number
    let flags = candidate == TypedColumns && contract.shape is @contract.Boolean
    let build = fn() {
      if budget.ledger is Some(ledger) && ledger.traffic is Some(traffic) {
        traffic.data_arrays += 1L
        if numeric || flags {
          traffic.validity_arrays += 1L
          traffic.validity_capacity += capacity.to_int64()
        }
      }
      if numeric {
        Numeric(FixedArray::make(capacity, 0.0), FixedArray::make(capacity, 0))
      } else if flags {
        Flags(FixedArray::make(capacity, 0), FixedArray::make(capacity, 0))
      } else {
        Generic(FixedArray::make(capacity, Null))
      }
    }
    if budget.ledger is Some(ledger) {
      let unit = if numeric { 9 } else if flags { 2 } else { 0 }
      let allocated = if unit > 0 && capacity > 2147483647 / unit {
        Err(LayoutStorageIssue::Limit)
      } else {
        allocate_owned_layout_buffer(
          ledger,
          if unit == 0 {
            capacity
          } else {
            1
          },
          capacity * unit,
          build,
        )
      }
      match allocated {
        Ok(buffer) => {
          owned.push(buffer)
          columns.push(buffer.value.unwrap())
        }
        Err(_) => {
          for buffer in owned {
            ignore(release_owned_layout_buffer(ledger, buffer))
          }
          columns.clear()
          return Err(RowLimit)
        }
      }
    } else {
      columns.push(build())
    }
  }
  Ok({
    columns,
    owned: if budget.ledger is Some(_) {
      Some(owned)
    } else {
      None
    },
    capacity,
    count: 0,
    closed: false,
    budget,
  })
}

///|
fn abort_layout_columns(builder : LayoutColumnBuilder) -> Unit {
  builder.closed = true
  if builder.owned is Some(buffers) {
    for buffer in buffers {
      ignore(release_owned_layout_buffer(buffer.lease.buffer.ledger, buffer))
    }
    builder.columns.clear()
  }
}

///|
fn append_layout_row(
  builder : LayoutColumnBuilder,
  row : Array[Value],
) -> Result[Unit, RowIssue] {
  append_layout_values(builder, row)
}

///|
fn[T : RowValues] append_layout_values(
  builder : LayoutColumnBuilder,
  row : T,
) -> Result[Unit, RowIssue] {
  if builder.closed {
    return Err(InvalidRows)
  }
  if builder.count >= builder.capacity ||
    RowValues::value_count(row) != builder.columns.length() {
    abort_layout_columns(builder)
    return Err(InvalidRows)
  }
  if !spend_control(builder.budget.work, RowValues::value_count(row)) {
    abort_layout_columns(builder)
    return Err(RowLimit)
  }
  let at = builder.count
  for column = 0; column < RowValues::value_count(row); column = column + 1 {
    match builder.columns[column] {
      Generic(values) => values[at] = RowValues::value_at(row, column)
      Numeric(values, valid) =>
        match RowValues::value_at(row, column) {
          Number(n) => {
            values[at] = n
            valid[at] = 1
          }
          Null => ()
          Boolean(_) | Text(_) | Captured(_) => {
            abort_layout_columns(builder)
            return Err(InvalidRows)
          }
        }
      Flags(values, valid) =>
        match RowValues::value_at(row, column) {
          Boolean(v) => {
            values[at] = if v { 1 } else { 0 }
            valid[at] = 1
          }
          Null => ()
          Number(_) | Text(_) | Captured(_) => {
            abort_layout_columns(builder)
            return Err(InvalidRows)
          }
        }
    }
  }
  if builder.budget.ledger is Some(ledger) && ledger.traffic is Some(traffic) {
    traffic.column_cell_transfers += RowValues::value_count(row).to_int64()
  }
  builder.count += 1
  Ok(())
}

///|
fn finish_layout_columns(
  builder : LayoutColumnBuilder,
) -> Result[LayoutStorage, RowIssue] {
  if builder.closed {
    return Err(InvalidRows)
  }
  builder.closed = true
  let width = builder.columns.length()
  let body = match builder.owned {
    Some(buffers) => {
      builder.columns.clear()
      OwnedColumnArrays(buffers)
    }
    None => ColumnArrays(builder.columns)
  }
  Ok({
    body,
    width,
    count: builder.count,
    selection: None,
    owned_selection: None,
  })
}

///|
test "column builders never publish a failed or already published construction" {
  let owner = row_owner("")
  let schema = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap().schema
  // A later cell fails after an earlier column has already been written.
  let failed = layout_column_builder(
    schema,
    ["a", "b"],
    2,
    TypedColumns,
    layout_allocation(1000, 1000, 1000),
  ).unwrap()
  assert_true(
    append_layout_row(failed, [Number(1.0), Boolean(true)]) is Err(InvalidRows),
  )
  assert_true(finish_layout_columns(failed) is Err(InvalidRows))
  assert_true(
    append_layout_row(failed, [Number(1.0), Number(2.0)]) is Err(InvalidRows),
  )
  // Fresh construction remains usable; publication prevents later mutation.
  let fresh = layout_column_builder(
    schema,
    ["a", "b"],
    2,
    TypedColumns,
    layout_allocation(1000, 1000, 1000),
  ).unwrap()
  append_layout_row(fresh, [Number(3.0), Number(4.0)]).unwrap()
  let published = finish_layout_columns(fresh).unwrap()
  assert_true(
    append_layout_row(fresh, [Number(8.0), Number(9.0)]) is Err(InvalidRows),
  )
  assert_true(finish_layout_columns(fresh) is Err(InvalidRows))
  assert_true(layout_cell(published, 0, 0) is Some(Number(3.0)))
  assert_true(layout_cell(published, 0, 1) is Some(Number(4.0)))
}

///|
// Uses the sole row evaluator. This is not a replacement sequence driver or a
// public backend selection API; the caller owns checked kernel/context setup.
fn evaluate_layout_body(
  kernel : @lower.PreparedKernel,
  input : LayoutRelation,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  storage_budget : LayoutAllocation,
  logical : LogicalBudget?,
  source? : RowBodySource? = None,
  output_id_override? : String? = None,
  maximum_rows? : Int? = None,
) -> Result[LayoutRelation, RowIssue] {
  let max_rows = match maximum_rows {
    Some(limit) => limit
    None => input.storage.count
  }
  let output_id = match output_id_override {
    Some(id) => id
    None =>
      @lower.node_id(
        @lower.node_at(
          @lower.bound_preparation(@lower.kernel_owner(kernel)),
          @lower.kernel_step(kernel),
        ).unwrap(),
      )
  }
  let body = match source {
    Some(body) => body
    None => PreparedBody(kernel)
  }
  evaluate_layout_source(
    body, input, output_id, max_rows, control, output, workspace, storage_budget,
    logical,
  )
}

///|
fn evaluate_layout_source(
  body : RowBodySource,
  input : LayoutRelation,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  storage_budget : LayoutAllocation,
  logical : LogicalBudget?,
) -> Result[LayoutRelation, RowIssue] {
  if input.candidate == RowLayout {
    return match
      evaluate_row_body(
        body,
        input,
        output_id,
        max_rows,
        control,
        output,
        workspace,
        ordered_budget=logical,
      ) {
      Err(issue) => Err(issue)
      Ok(table) =>
        Ok({
          ..input,
          id: table.id,
          names: table.names,
          storage: {
            body: RowArrays(table.rows),
            width: table.names.length(),
            count: table.rows.length(),
            selection: None,
            owned_selection: None,
          },
        })
    }
  }
  let schema = match body {
    PreparedBody(kernel) => @lower.kernel_output_schema(kernel)
    Projection(view) => @lower.projection_output_schema(view)
  }
  let filtering = match body {
    PreparedBody(kernel) => @lower.kernel_body(kernel) is @lower.Filter(_)
    Projection(_) => false
  }
  let kept : Array[Int] = []
  let mut projection : Array[Int]? = None
  let mut builder : LayoutColumnBuilder? = None
  let names = match
    evaluate_row_body_into(
      body,
      input,
      max_rows,
      control,
      output,
      workspace,
      fn(row, source, names, resolved_projection) {
        if resolved_projection is Some(indices) {
          projection = Some(indices)
          Ok(())
        } else if filtering {
          if !reserve_slots(storage_budget.slots, 1) ||
            !spend_control(storage_budget.work, 1) {
            Err(RowLimit)
          } else {
            kept.push(source)
            Ok(())
          }
        } else {
          if builder is None {
            builder = Some(
              match
                layout_column_builder(
                  schema,
                  names,
                  input.storage.count,
                  input.candidate,
                  storage_budget,
                ) {
                Ok(b) => b
                Err(issue) => return Err(issue)
              },
            )
          }
          append_layout_row(builder.unwrap(), row)
        }
      },
      ordered_budget=logical,
    ) {
    Ok(names) => names
    Err(issue) => {
      if builder is Some(b) {
        abort_layout_columns(b)
      }
      return Err(issue)
    }
  }
  let storage = if projection is Some(indices) {
    match project_layout(input.storage, indices, storage_budget) {
      Ok(value) => value
      Err(Limit) => return Err(RowLimit)
      Err(Shape) => return Err(InvalidRows)
    }
  } else if filtering {
    match select_layout_rows(input.storage, kept, storage_budget) {
      Ok(value) => value
      Err(Limit) => return Err(RowLimit)
      Err(Shape) => return Err(InvalidRows)
    }
  } else {
    let b = match builder {
      Some(b) => b
      None =>
        match
          layout_column_builder(
            schema,
            names,
            0,
            input.candidate,
            storage_budget,
          ) {
          Ok(b) => b
          Err(issue) => return Err(issue)
        }
    }
    match finish_layout_columns(b) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  Ok({ ..input, id: output_id, names, storage, })
}

///|
test "shared evaluator builds typed shadow output without a retained row matrix" {
  let owner = row_owner(
    ",{\"derive\":[{\"a\":\"a > 0\"},{\"old_b\":\"b\"}]},{\"filter\":\"a\"},{\"select\":[\"old_b\",\"a\"]}",
  )
  let captured = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let mut input = layout_relation(captured, candidate)
    let control = { remaining: 100000, max_frames: 100, }
    let output = row_output()
    let physical = layout_allocation(100000, 100000, 100000)
    for step = 1; step <= 3; step = step + 1 {
      input = evaluate_layout_body(
        row_kernel(owner, step),
        input,
        control,
        output,
        { limit: 100000, live: 0, peak: 0, },
        physical,
        Some(ordered_row_budget(10000L, 10000L)),
      ).unwrap()
      if step == 1 && candidate == TypedColumns {
        guard input.storage.body is ColumnArrays(columns) else {
          fail("columns")
        }
        assert_true(columns[0] is Flags(_, _))
      }
    }
    assert_eq(input.names, ["old_b", "a"])
    assert_eq(input.storage.count, 1)
    assert_true(layout_cell(input.storage, 0, 0) is Some(Number(0)))
    assert_true(layout_cell(input.storage, 0, 1) is Some(Boolean(true)))
    if candidate != RowLayout {
      assert_true(input.storage.body is ColumnArrays(_))
    }
  }
}
