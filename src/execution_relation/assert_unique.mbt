///|
/// Validate the checked scalar tuple without changing row order or publishing
/// a partial output. Sorting is an internal bounded index only.
fn[T : RelationRows] validate_unique_rows(
  input : T,
  keys : Array[@schema.FieldName],
  ordinals : Map[String, Int],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Unit, RowIssue] {
  let baseline = workspace.live
  let run = fn() -> Result[Unit, RowIssue] {
    if keys.is_empty() ||
      !reserve_slots(workspace, keys.length()) ||
      !spend_control(control, keys.length()) {
      return Err(RowLimit)
    }
    let order : Array[ColumnOrder] = []
    for key_index = 0; key_index < keys.length(); key_index = key_index + 1 {
      let name = @schema.reference_name(keys[key_index])
      if !spend_control_text(control, name) {
        return Err(RowLimit)
      }
      guard ordinals.get(name) is Some(column) else { return Err(InvalidRows) }
      order.push({ column, descending: false, nulls_first: false, })
      for row = 0; row < IndexedRows::row_count(input); row = row + 1 {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        if IndexedRows::read_cell(input, row, column) is Null {
          return Err(AssertionNullKey(row, key_index))
        }
      }
    }
    let sorted = match stable_order_indices(input, order, control, workspace) {
      Ok(indices) => indices
      Err(InvalidInput) => return Err(InvalidRows)
      Err(Limit) => return Err(RowLimit)
      Err(Scalar(issue)) => return Err(Comparison(issue))
    }
    for i = 1; i < sorted.length(); i = i + 1 {
      match
        compare_row_indices(input, sorted[i - 1], sorted[i], order, control) {
        Ok(0) => return Err(AssertionDuplicate(sorted[i - 1], sorted[i]))
        Ok(_) => ()
        Err(InvalidInput) => return Err(InvalidRows)
        Err(Limit) => return Err(RowLimit)
        Err(Scalar(issue)) => return Err(Comparison(issue))
      }
    }
    Ok(())
  }
  let result = run()
  release_slots(workspace, workspace.live - baseline)
  result
}
