///|
/// Expand authored unpivot column occurrences in input-row then column order.
/// Repeated columns remain repeated rows and nested values are retained without
/// coercion or serialization.
fn[T : RelationRows] evaluate_unpivot_into(
  kernel : @lower.PreparedKernel,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  emit : (Array[Value]) -> Result[Unit, RowIssue],
) -> Result[Array[String], RowIssue] {
  guard @lower.kernel_unpivot_outputs(kernel)
    is Some((name_column, value_column)) else {
    return Err(InvalidRows)
  }
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  let names = input.field_names()
  let width = names.length()
  let ordinals : Map[String, Int] = Map([])
  for i = 0; i < width; i = i + 1 {
    if !spend_control(control, 1) || !spend_control_text(control, names[i]) {
      return Err(RowLimit)
    }
    if ordinals.contains(names[i]) {
      return Err(InvalidRows)
    }
    ordinals[names[i]] = i
  }
  let columns = @lower.kernel_unpivot_column_count(kernel)
  let keep = @lower.kernel_unpivot_keep_count(kernel)
  if columns <= 0 ||
    !reserve_slots(workspace, columns) ||
    !reserve_slots(workspace, columns) ||
    !reserve_slots(workspace, keep) ||
    !spend_control(control, columns + keep) {
    return Err(RowLimit)
  }
  let column_ordinals : Array[Int] = []
  let labels : Array[String] = []
  for i = 0; i < columns; i = i + 1 {
    let field = @lower.kernel_unpivot_column_at(kernel, i).unwrap()
    let name = @schema.reference_name(field)
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    guard ordinals.get(name) is Some(ordinal) else { return Err(InvalidRows) }
    column_ordinals.push(ordinal)
    labels.push(name)
  }
  let kept : Map[String, Int] = Map([])
  for i = 0; i < keep; i = i + 1 {
    let name = @schema.reference_name(
      @lower.kernel_unpivot_keep_at(kernel, i).unwrap(),
    )
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    guard ordinals.get(name) is Some(ordinal) else { return Err(InvalidRows) }
    if kept.contains(name) {
      return Err(InvalidRows)
    }
    kept[name] = ordinal
  }
  let checked_output = @lower.kernel_output_schema(kernel)
  let output_names = Array::makei(@schema.field_count(checked_output), i => {
    @schema.reference_name(@schema.field_at(checked_output, i).unwrap().name)
  })
  if output_names.length() != keep + 2 {
    return Err(InvalidRows)
  }
  for name in output_names {
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    if name != name_column && name != value_column && !kept.contains(name) {
      return Err(InvalidRows)
    }
  }
  let rows = IndexedRows::row_count(input)
  if !reserve_slots(workspace, rows) ||
    !reserve_slots(workspace, width) ||
    !reserve_slots(workspace, output_names.length()) {
    return Err(RowLimit)
  }
  let mut emitted = 0
  for source = 0; source < rows; source = source + 1 {
    if IndexedRows::row_width(input, source) != width {
      return Err(InvalidRows)
    }
    if !spend_control(control, 1) || !reserve_slots(workspace, width) {
      return Err(RowLimit)
    }
    for occurrence = 0; occurrence < columns; occurrence = occurrence + 1 {
      if emitted >= max_rows ||
        !reserve_slots(workspace, output_names.length()) ||
        !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let row = output_names.map(name => {
        if name == name_column {
          Text(labels[occurrence])
        } else if name == value_column {
          IndexedRows::read_cell(input, source, column_ordinals[occurrence])
        } else {
          IndexedRows::read_cell(input, source, kept.get(name).unwrap())
        }
      })
      if !retain_row(row, output_names, output) {
        return Err(RowLimit)
      }
      match emit(row) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      emitted += 1
    }
  }
  Ok(output_names)
}

///|
fn[T : RelationRows] evaluate_unpivot_rows(
  kernel : @lower.PreparedKernel,
  input : T,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  let result : Array[Array[Value]] = []
  let names = match
    evaluate_unpivot_into(kernel, input, max_rows, control, output, workspace, row => {
      result.push(row)
      Ok(())
    }) {
    Ok(names) => names
    Err(issue) => return Err(issue)
  }
  Ok({
    owner: RelationRows::checked_owner(input),
    id: output_id,
    names,
    rows: result,
  })
}

///|
// Build mixed-domain output directly in sealed columns. This path is selected
// before execution for an existing physical completion and never retries after
// a semantic or capacity failure.
fn evaluate_unpivot_columns(
  kernel : @lower.PreparedKernel,
  input : CompletedTable,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[CompletedTable, RowIssue] {
  let columns : Array[Array[Value]] = []
  let names = match
    evaluate_unpivot_into(kernel, input, max_rows, control, output, workspace, row => {
      if columns.is_empty() {
        for _value in row {
          columns.push([])
        }
      }
      if row.length() != columns.length() {
        return Err(InvalidRows)
      }
      for i, value in row {
        columns[i].push(value)
      }
      Ok(())
    }) {
    Ok(names) => names
    Err(issue) => return Err(issue)
  }
  if columns.is_empty() {
    for _name in names {
      columns.push([])
    }
  }
  Ok(
    ColumnTable({
      owner: RelationRows::checked_owner(input),
      id: output_id,
      names,
      columns,
      count: if columns.is_empty() {
        0
      } else {
        columns[0].length()
      },
      selection: None,
    }),
  )
}
