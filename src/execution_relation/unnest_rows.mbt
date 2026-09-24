///|
/// Expand an admitted array without preallocating from its declared bound.
/// Input-row and element order are retained exactly; outer synthetic rows use
/// NULL for both the element and exposed index.
fn[T : RelationRows] evaluate_unnest_into(
  kernel : @lower.PreparedKernel,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  emit : (Array[Value]) -> Result[Unit, RowIssue],
) -> Result[Array[String], RowIssue] {
  guard @lower.kernel_unnest(kernel)
    is Some((column, element, index_name, outer, max_items)) else {
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
  let source_name = @schema.reference_name(column)
  let mut source_column = -1
  let ordinals : Map[String, Int] = Map([])
  for i = 0; i < width; i = i + 1 {
    if !spend_control(control, 1) || !spend_control_text(control, names[i]) {
      return Err(RowLimit)
    }
    if names[i] == source_name {
      if source_column >= 0 {
        return Err(InvalidRows)
      }
      source_column = i
    }
    if ordinals.contains(names[i]) {
      return Err(InvalidRows)
    }
    ordinals[names[i]] = i
  }
  if source_column < 0 {
    return Err(InvalidRows)
  }
  let checked_output = @lower.kernel_output_schema(kernel)
  let output_width = @schema.field_count(checked_output)
  let added = if index_name is Some(_) { 2 } else { 1 }
  if output_width < added || output_width - added != width {
    return Err(InvalidRows)
  }
  for i = 0; i < output_width; i = i + 1 {
    let name = @schema.reference_name(
      @schema.field_at(checked_output, i).unwrap().name,
    )
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    if name != element &&
      !(index_name is Some(index) && name == index) &&
      !ordinals.contains(name) {
      return Err(InvalidRows)
    }
  }
  let mut emitted = 0
  let rows = IndexedRows::row_count(input)
  if !reserve_slots(workspace, rows) ||
    !reserve_slots(workspace, width) ||
    !reserve_slots(workspace, output_width) {
    return Err(RowLimit)
  }
  let output_names = Array::makei(output_width, i => {
    @schema.reference_name(@schema.field_at(checked_output, i).unwrap().name)
  })
  for source = 0; source < rows; source = source + 1 {
    if IndexedRows::row_width(input, source) != width {
      return Err(InvalidRows)
    }
    if !spend_control(control, 1) || !reserve_slots(workspace, width) {
      return Err(RowLimit)
    }
    let cell = IndexedRows::read_cell(input, source, source_column)
    let mut row_emitted = false
    match cell {
      Captured(@admitted.Array(items)) => {
        let count = @admitted.element_count(items)
        if max_items is Some(limit) && count.to_int64() > limit {
          return Err(InvalidRows)
        }
        for item_index = 0; item_index < count; item_index = item_index + 1 {
          guard @admitted.element_at(items, item_index) is Some(item) else {
            return Err(InvalidRows)
          }
          if emitted >= max_rows ||
            !reserve_slots(workspace, output_names.length()) ||
            !spend_control(control, 1) {
            return Err(RowLimit)
          }
          let row = output_names.map(name => {
            if name == element {
              capture(item)
            } else if index_name is Some(index) && name == index {
              Number(item_index.to_double())
            } else {
              IndexedRows::read_cell(input, source, ordinals.get(name).unwrap())
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
          row_emitted = true
        }
      }
      Null => ()
      _ => return Err(InvalidRows)
    }
    if outer && !row_emitted {
      if emitted >= max_rows ||
        !reserve_slots(workspace, output_names.length()) ||
        !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let row = output_names.map(name => {
        if name == element || (index_name is Some(index) && name == index) {
          Null
        } else {
          IndexedRows::read_cell(input, source, ordinals.get(name).unwrap())
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
fn[T : RelationRows] evaluate_unnest_rows(
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
    evaluate_unnest_into(kernel, input, max_rows, control, output, workspace, row => {
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
// Expand an existing physical completion directly into sealed columns. The
// representation is selected before execution and never used as a retry after
// a semantic or capacity failure.
fn evaluate_unnest_columns(
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
    evaluate_unnest_into(kernel, input, max_rows, control, output, workspace, row => {
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
