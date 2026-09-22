///|
fn asof_null(value : Value) -> Bool {
  value is Null || value is Captured(@admitted.Null)
}

///|
fn[L : RelationRows, R : RelationRows] evaluate_asof_join_rows(
  kernel : @lower.PreparedAsOfJoin,
  left : L,
  right : R,
  max_rows : Int,
  max_search_visits : Int64,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  selected_ceiling? : (Int, Int64)? = None,
) -> Result[Table, RowIssue] {
  let owner = @lower.asof_join_owner(kernel)
  if !physical_equal(left.checked_owner(), owner) ||
    !physical_equal(right.checked_owner(), owner) {
    return Err(OwnerMismatch)
  }
  if left.relation_id() != @lower.asof_join_input(kernel, true) ||
    right.relation_id() != @lower.asof_join_input(kernel, false) {
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
  let mut retained = 0
  let run = fn() -> Result[Table, RowIssue] {
    let left_names = left.field_names()
    let right_names = right.field_names()
    let left_time = match
      resolve_column(left_names, @lower.asof_join_time(kernel, true), control) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let right_time = match
      resolve_column(right_names, @lower.asof_join_time(kernel, false), control) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let keys : Array[(Int, Int)] = []
    for index in 0..<@lower.asof_join_key_count(kernel) {
      if !reserve_slots(workspace, 2) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let (left_field, right_field) = @lower.asof_join_key_at(kernel, index).unwrap()
      let left_column = match resolve_column(left_names, left_field, control) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let right_column = match
        resolve_column(right_names, right_field, control) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      keys.push((left_column, right_column))
    }
    let identity_fields : Array[@schema.FieldName] = []
    let identity_order : Array[ColumnOrder] = [
      { column: left_time, descending: false, nulls_first: false, },
    ]
    let left_ordinals : Map[String, Int] = Map([])
    for index, name in left_names {
      left_ordinals[name] = index
    }
    for index in 0..<@lower.asof_join_identity_count(kernel) {
      guard @lower.asof_join_identity_at(kernel, index) is Some(field) else {
        return Err(InvalidRows)
      }
      let column = match resolve_column(left_names, field, control) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !reserve_slots(workspace, 2) {
        return Err(RowLimit)
      }
      identity_fields.push(field)
      identity_order.push({ column, descending: false, nulls_first: false, })
    }
    match
      validate_unique_rows(
        left, identity_fields, left_ordinals, control, workspace,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let ties : Array[Int] = []
    for index in 0..<@lower.asof_join_tie_break_count(kernel) {
      guard @lower.asof_join_tie_break_at(kernel, index) is Some(field) else {
        return Err(InvalidRows)
      }
      if !reserve_slots(workspace, 1) {
        return Err(RowLimit)
      }
      match resolve_column(right_names, field, control) {
        Ok(column) => ties.push(column)
        Err(issue) => return Err(issue)
      }
    }
    let left_clocks : Array[Int64] = []
    let right_clocks : Array[Int64] = []
    if !reserve_slots(workspace, left_count) ||
      !reserve_slots(workspace, right_count) {
      return Err(RowLimit)
    }
    for row in 0..<left_count {
      match
        interval_clock(
          IndexedRows::read_cell(left, row, left_time),
          @lower.asof_join_uses_timestamp(kernel, true),
          control,
        ) {
        Ok(value) => left_clocks.push(value)
        Err(issue) => return Err(issue)
      }
    }
    for row in 0..<right_count {
      match
        interval_clock(
          IndexedRows::read_cell(right, row, right_time),
          @lower.asof_join_uses_timestamp(kernel, false),
          control,
        ) {
        Ok(value) => right_clocks.push(value)
        Err(issue) => return Err(issue)
      }
    }
    let ordered_left = match
      stable_order_indices(left, identity_order, control, workspace) {
      Ok(value) => value
      Err(issue) => return Err(ordering_row_issue(issue))
    }
    let names : Array[String] = []
    let columns : Array[(Bool, Int)] = []
    for index in 0..<@lower.asof_join_field_count(kernel) {
      if !reserve_slots(workspace, 3) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let field = @lower.asof_join_field_at(kernel, index).unwrap()
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
        resolve_column(
          if on_left {
            left_names
          } else {
            right_names
          },
          source,
          control,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      columns.push((on_left, column))
    }
    let mut ceiling = max_rows
    if selected_ceiling is Some((step, bound)) &&
      step == @lower.asof_join_step(kernel) {
      if bound < 0L {
        return Err(InvalidRowLimits)
      }
      if bound < ceiling.to_int64() {
        ceiling = bound.to_int()
      }
    }
    let rows : Array[Array[Value]] = []
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
          Err(issue) => return Err(ordering_row_issue(issue))
        }
      }
      Ok(true)
    }
    let compare_tie = fn(first : Int, second : Int) -> Result[Int, RowIssue] {
      for column in ties {
        let first_value = IndexedRows::read_cell(right, first, column)
        let second_value = IndexedRows::read_cell(right, second, column)
        let first_null = asof_null(first_value)
        let second_null = asof_null(second_value)
        if first_null || second_null {
          if !spend_control(control, 1) {
            return Err(RowLimit)
          }
          if first_null != second_null {
            return Ok(if first_null { 1 } else { -1 })
          }
        }
        match compare_complete_value(first_value, second_value, control) {
          Ok(0) => ()
          Ok(value) => return Ok(value)
          Err(issue) => return Err(ordering_row_issue(issue))
        }
      }
      Ok(0)
    }
    let direction = @lower.asof_join_direction(kernel)
    let tolerance = @lower.asof_join_tolerance(kernel)
    for left_row in ordered_left {
      let mut best : Int? = None
      let mut best_distance = 0L
      let mut best_tied_with : Int? = None
      for right_row in 0..<right_count {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        let matches = match equal_keys(left_row, right_row) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if matches {
          let left_clock = left_clocks[left_row]
          let right_clock = right_clocks[right_row]
          let eligible = match direction {
            @asof.AsOfDirection::Backward => right_clock <= left_clock
            @asof.AsOfDirection::Forward => right_clock >= left_clock
            @asof.AsOfDirection::Nearest => true
          }
          let distance = if right_clock <= left_clock {
            left_clock - right_clock
          } else {
            right_clock - left_clock
          }
          if eligible && distance <= tolerance {
            let better = match best {
              None => true
              Some(prior) =>
                if distance < best_distance {
                  true
                } else if distance > best_distance {
                  false
                } else {
                  match compare_tie(right_row, prior) {
                    Ok(0) => {
                      best_tied_with = Some(right_row)
                      false
                    }
                    Ok(value) => value < 0
                    Err(issue) => return Err(issue)
                  }
                }
            }
            if better {
              best = Some(right_row)
              best_distance = distance
              best_tied_with = None
            }
          }
        }
      }
      if best is Some(prior) && best_tied_with is Some(other) {
        return Err(AsOfTopTie(left_row, prior, other))
      }
      if best is Some(_) || @lower.asof_join_kind(kernel) == @join.Left {
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
            match best {
              Some(right_row) =>
                IndexedRows::read_cell(right, right_row, pair.1)
              None => Null
            }
          }
        })
        if !retain_row(row, names, output) {
          return Err(RowLimit)
        }
        rows.push(row)
      }
    }
    Ok({
      owner,
      id: @lower.node_id(
        @lower.node_at(
          @lower.bound_preparation(owner),
          @lower.asof_join_step(kernel),
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
