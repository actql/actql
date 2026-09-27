///|
/// Physical coordinates only. The caller owns checked key/count resolution,
/// canonical output construction, admission and publication. None denotes the
/// synthetic empty global group; it never authorizes reading an input row.
priv struct CountedGroup {
  representative : Int?
  counts : Array[Int]
}

///|
/// Reuse scalar comparison and stable row-index ordering across layouts.
/// Count increments are bounded by the input's Int-sized row count, hence exact
/// when later converted to binary64. This is not a language-wide count limit.
fn[T : IndexedRows] count_groups(
  input : T,
  order : Array[ColumnOrder],
  columns : Array[Int?],
  max_groups : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
  count_if_columns? : Array[Bool] = [],
) -> Result[Array[CountedGroup], OrderingIssue] {
  if max_groups < 0 ||
    (
      !count_if_columns.is_empty() &&
      count_if_columns.length() != columns.length()
    ) ||
    control.remaining < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidInput)
  }
  let baseline = workspace.live
  let mut kept = 0
  let run = fn() -> Result[Array[CountedGroup], OrderingIssue] {
    for column in columns {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      if column is Some(i) && (i < 0 || i >= input.column_count()) {
        return Err(InvalidInput)
      }
    }
    let indices = match stable_order_indices(input, order, control, workspace) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    let groups : Array[CountedGroup] = []
    let add = fn(row : Int?) -> Bool {
      if groups.length() >= max_groups ||
        !spend_control(control, 1) ||
        !spend_control(control, columns.length()) ||
        !reserve_slots(workspace, 1) ||
        !reserve_slots(workspace, columns.length()) {
        return false
      }
      kept += 1
      kept += columns.length()
      groups.push({
        representative: row,
        counts: Array::make(columns.length(), 0),
      })
      true
    }
    if indices.is_empty() && order.is_empty() {
      if !add(None) {
        return Err(Limit)
      }
    }
    for row in indices {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      let new_group = if groups.is_empty() {
        true
      } else {
        let previous = groups[groups.length() - 1].representative.unwrap()
        match compare_row_indices(input, previous, row, order, control) {
          Ok(c) => c != 0
          Err(e) => return Err(e)
        }
      }
      if new_group && !add(Some(row)) {
        return Err(Limit)
      }
      let counts = groups[groups.length() - 1].counts
      for i in 0..<columns.length() {
        if !spend_control(control, 1) {
          return Err(Limit)
        }
        let counted = match columns[i] {
          None => true
          Some(column) =>
            if !count_if_columns.is_empty() && count_if_columns[i] {
              match input.read_cell(row, column) {
                Boolean(true) => true
                Boolean(false) | Null => false
                _ => return Err(InvalidInput)
              }
            } else {
              !(input.read_cell(row, column) is Null)
            }
        }
        if counted {
          counts[i] += 1
        }
      }
    }
    Ok(groups)
  }
  let result = run()
  match result {
    Ok(_) => release_slots(workspace, workspace.live - baseline - kept)
    Err(_) => release_slots(workspace, workspace.live - baseline)
  }
  result
}
