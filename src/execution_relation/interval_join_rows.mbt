///|
fn interval_clock(
  value : Value,
  timestamp : Bool,
  control : ControlBudget,
) -> Result[Int64, RowIssue] {
  if !spend_control(control, 1) {
    return Err(RowLimit)
  }
  if timestamp {
    guard value is Captured(@admitted.Timestamp(text)) &&
      spend_control_text(control, text) &&
      @admitted.timestamp_epoch_milliseconds(text) is Some(milliseconds) else {
      return Err(InvalidRows)
    }
    Ok(milliseconds)
  } else {
    guard value is Number(number) &&
      @scalar.read_safe_integer(number) is Some(milliseconds) else {
      return Err(InvalidRows)
    }
    Ok(milliseconds)
  }
}

///|
fn interval_ordering_issue(issue : OrderingIssue) -> RowIssue {
  match issue {
    InvalidInput => InvalidRows
    Limit => RowLimit
    Scalar(issue) => Comparison(issue)
  }
}

///|
fn[L : RelationRows, R : RelationRows] evaluate_interval_join_rows(
  kernel : @lower.PreparedIntervalJoin,
  left : L,
  right : R,
  max_rows : Int,
  max_search_visits : Int64,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  selected_ceiling? : (Int, Int64)? = None,
) -> Result[Table, RowIssue] {
  let owner = @lower.interval_join_owner(kernel)
  if !physical_equal(left.checked_owner(), owner) ||
    !physical_equal(right.checked_owner(), owner) {
    return Err(OwnerMismatch)
  }
  if left.relation_id() != @lower.interval_join_input(kernel, true) ||
    right.relation_id() != @lower.interval_join_input(kernel, false) {
    return Err(InputMismatch)
  }
  if max_rows < 0 ||
    max_search_visits < 0L ||
    workspace.live != 0 ||
    workspace.peak != 0 ||
    workspace.limit < 0 {
    return Err(InvalidRowLimits)
  }
  let left_count = IndexedRows::row_count(left)
  let right_count = IndexedRows::row_count(right)
  if left_count > max_rows || right_count > max_rows {
    return Err(RowLimit)
  }
  if right_count != 0 &&
    left_count.to_int64() > max_search_visits / right_count.to_int64() {
    return Err(RowLimit)
  }
  let resolve = fn(
    names : Array[String],
    field : @schema.FieldName,
  ) -> Result[Int, RowIssue] {
    let reference = @schema.reference_name(field)
    for index, name in names {
      if !spend_control(control, 1) ||
        !spend_control_text(control, reference) ||
        !spend_control_text(control, name) {
        return Err(RowLimit)
      }
      if name == reference {
        return Ok(index)
      }
    }
    Err(InvalidRows)
  }
  let mut retained = 0
  let run = fn() -> Result[Table, RowIssue] {
    let keys : Array[(Int, Int)] = []
    for index in 0..<@lower.interval_join_key_count(kernel) {
      if !reserve_slots(workspace, 2) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let (left_field, right_field) = @lower.interval_join_key_at(kernel, index).unwrap()
      let left_column = match resolve(left.field_names(), left_field) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let right_column = match resolve(right.field_names(), right_field) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      keys.push((left_column, right_column))
    }
    let resolve_operand = fn(
      operand : @join.TemporalOperand,
      on_left : Bool,
    ) -> Result[(Int, Int?), RowIssue] {
      match operand {
        @join.Point(time) =>
          resolve(
            if on_left {
              left.field_names()
            } else {
              right.field_names()
            },
            time,
          ).map(column => (column, None))
        @join.Interval(start, end) => {
          let start_column = match
            resolve(
              if on_left {
                left.field_names()
              } else {
                right.field_names()
              },
              start,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          resolve(
            if on_left {
              left.field_names()
            } else {
              right.field_names()
            },
            end,
          ).map(end_column => (start_column, Some(end_column)))
        }
      }
    }
    let left_operand = match
      resolve_operand(@lower.interval_join_operand(kernel, true), true) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let right_operand = match
      resolve_operand(@lower.interval_join_operand(kernel, false), false) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let left_starts : Array[Int64] = []
    let left_ends : Array[Int64] = []
    let right_starts : Array[Int64] = []
    let right_ends : Array[Int64] = []
    let left_slots = if left_operand.1 is Some(_) { 2 } else { 1 }
    if left_count != 0 &&
      left_count > (workspace.limit - workspace.live) / left_slots {
      return Err(RowLimit)
    }
    if !reserve_slots(workspace, left_count * left_slots) {
      return Err(RowLimit)
    }
    if right_count != 0 && right_count > (workspace.limit - workspace.live) / 2 {
      return Err(RowLimit)
    }
    if !reserve_slots(workspace, right_count * 2) {
      return Err(RowLimit)
    }
    let timestamp = @lower.interval_join_uses_timestamps(kernel)
    for row in 0..<left_count {
      let start = match
        interval_clock(
          IndexedRows::read_cell(left, row, left_operand.0),
          timestamp,
          control,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      left_starts.push(start)
      if left_operand.1 is Some(column) {
        let end = match
          interval_clock(
            IndexedRows::read_cell(left, row, column),
            timestamp,
            control,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if start >= end {
          return Err(InvalidRows)
        }
        left_ends.push(end)
      }
    }
    for row in 0..<right_count {
      let start = match
        interval_clock(
          IndexedRows::read_cell(right, row, right_operand.0),
          timestamp,
          control,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let end_column = match right_operand.1 {
        Some(value) => value
        None => return Err(InvalidRows)
      }
      let end = match
        interval_clock(
          IndexedRows::read_cell(right, row, end_column),
          timestamp,
          control,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if start >= end {
        return Err(InvalidRows)
      }
      right_starts.push(start)
      right_ends.push(end)
    }
    let names : Array[String] = []
    let columns : Array[(Bool, Int)] = []
    for index in 0..<@lower.interval_join_field_count(kernel) {
      if !reserve_slots(workspace, 3) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let field = @lower.interval_join_field_at(kernel, index).unwrap()
      let name = @schema.reference_name(field.output)
      if !spend_control_text(control, name) {
        return Err(RowLimit)
      }
      names.push(name)
      retained += 1
      let (on_left, source) = match field.input {
        @schema.Qualified(side, name) =>
          (side == @schema.Left, @schema.Unqualified(name))
        _ => return Err(InvalidRows)
      }
      let column = match
        resolve(
          if on_left {
            left.field_names()
          } else {
            right.field_names()
          },
          source,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      columns.push((on_left, column))
    }
    let mut ceiling = match @lower.interval_join_output_limit(kernel) {
      Some(limit) if limit < max_rows.to_int64() => limit.to_int()
      _ => max_rows
    }
    if selected_ceiling is Some((step, bound)) &&
      step == @lower.interval_join_step(kernel) {
      if bound < 0L {
        return Err(InvalidRowLimits)
      }
      if bound < ceiling.to_int64() {
        ceiling = bound.to_int()
      }
    }
    let rows : Array[Array[Value]] = []
    let emit = fn(left_row : Int, right_row : Int?) -> Result[Unit, RowIssue] {
      if rows.length() == ceiling ||
        !reserve_slots(workspace, 1 + names.length()) ||
        !spend_control(control, 1 + names.length()) {
        return Err(RowLimit)
      }
      retained += 1 + names.length()
      let row = columns.map(pair => {
        if pair.0 {
          IndexedRows::read_cell(left, left_row, pair.1)
        } else {
          match right_row {
            Some(row) => IndexedRows::read_cell(right, row, pair.1)
            None => Null
          }
        }
      })
      if !retain_row(row, names, output) {
        return Err(RowLimit)
      }
      rows.push(row)
      Ok(())
    }
    let equal_keys = fn(
      left_row : Int,
      right_row : Int,
    ) -> Result[Bool, RowIssue] {
      for (left_column, right_column) in keys {
        let left_value = IndexedRows::read_cell(left, left_row, left_column)
        let right_value = IndexedRows::read_cell(right, right_row, right_column)
        if left_value is Null || right_value is Null {
          if !spend_control(control, 1) {
            return Err(RowLimit)
          }
          return Ok(false)
        }
        match compare_complete_value(left_value, right_value, control) {
          Ok(0) => ()
          Ok(_) => return Ok(false)
          Err(issue) => return Err(interval_ordering_issue(issue))
        }
      }
      Ok(true)
    }
    let kind = @lower.interval_join_kind(kernel)
    let overlap = @lower.interval_join_mode(kernel) == @join.Overlap
    for left_row in 0..<left_count {
      let mut matched = false
      for right_row in 0..<right_count {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        let keys_match = match equal_keys(left_row, right_row) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        let temporal_match = keys_match &&
          (if overlap {
            left_starts[left_row] < right_ends[right_row] &&
            right_starts[right_row] < left_ends[left_row]
          } else {
            right_starts[right_row] <= left_starts[left_row] &&
            left_starts[left_row] < right_ends[right_row]
          })
        if temporal_match {
          matched = true
          if kind == @join.Inner || kind == @join.Left {
            match emit(left_row, Some(right_row)) {
              Ok(_) => ()
              Err(issue) => return Err(issue)
            }
          }
        }
      }
      if kind == @join.Left && !matched {
        match emit(left_row, None) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      } else if (kind == @join.Semi && matched) ||
        (kind == @join.Anti && !matched) {
        match emit(left_row, None) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
    }
    Ok({
      owner,
      id: @lower.node_id(
        @lower.node_at(
          @lower.bound_preparation(owner),
          @lower.interval_join_step(kernel),
        ).unwrap(),
      ),
      names,
      rows,
    })
  }
  let result = run()
  let keep = match result {
    Ok(_) => retained
    Err(_) => 0
  }
  release_slots(workspace, workspace.live - keep)
  result
}
