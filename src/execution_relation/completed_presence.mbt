///|
/// Select physical representation before execution, not as failure recovery.
/// The same sequence Store owns either representation and its resource lease.
fn completed_table_from_capture(
  captured : CapturedRows,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[CompletedTable, RowIssue] {
  if @schema.all_fields_required(captured.schema) {
    return table_from_capture_bounded(captured, control, workspace).map(table => {
      RowTable(table)
    })
  }
  let width = @schema.field_count(captured.schema)
  let prepared = @lower.bound_preparation(captured.owner)
  let id = match captured.origin {
    SuppliedInput(index) => @lower.input_id(prepared, index).unwrap()
    ValuesNode(_) => return Err(InvalidRows)
  }
  if !reserve_slots(workspace, width) ||
    !reserve_slots(workspace, captured.presence_rows.length()) ||
    !spend_control(control, captured.presence_rows.length()) {
    return Err(RowLimit)
  }
  let names = []
  for column in 0..<width {
    let field = @schema.field_at(captured.schema, column).unwrap()
    let name = @schema.reference_name(field.name)
    if !spend_control(control, 1) || !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    names.push(name)
  }
  let rows = []
  for row in captured.presence_rows {
    if !physical_equal(row.schema, captured.schema) ||
      row.cells.length() != width {
      return Err(InvalidRows)
    }
    // Source and destination presence containers coexist until handoff.
    if !reserve_slots(workspace, width) ||
      !reserve_slots(workspace, width) ||
      !spend_control(control, width) {
      return Err(RowLimit)
    }
    rows.push({ ..row, cells: row.cells.copy(), })
  }
  Ok(PresenceTable({ owner: captured.owner, id, names, rows, }))
}
