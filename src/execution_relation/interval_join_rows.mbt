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
priv enum IntervalSearchPhase {
  ComparePairs
  EmitLeftRemainder
  FinishSearch
}

///|
/// Private resumable cursor for the Cartesian search. Preparation and output
/// construction remain owned by the surrounding evaluator; this state owns
/// only the position at which the next exact pair must be considered.
priv struct IntervalSearchState {
  left_count : Int
  right_count : Int
  kind : @join.Kind
  overlap : Bool
  left_starts : Array[Int64]
  left_ends : Array[Int64]
  right_starts : Array[Int64]
  right_ends : Array[Int64]
  equal_keys : (Int, Int) -> Result[Bool, RowIssue]
  emit : (Int, Int?) -> Result[Unit, RowIssue]
  mut phase : IntervalSearchPhase
  mut left_row : Int
  mut right_row : Int
  mut matched : Bool
}

///|
priv struct IntervalSearchExecution {
  session : @bounded.Session[IntervalSearchState, Unit, RowIssue]
  mut token : @bounded.Token?
}

///|
priv enum IntervalSearchPoll {
  IntervalSearchContinue(progress~ : Int64, work~ : Int64)
  IntervalSearchComplete(progress~ : Int64, work~ : Int64)
  IntervalSearchFailed(RowIssue, progress~ : Int64, work~ : Int64)
  IntervalSearchStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn interval_search_step(
  state : IntervalSearchState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[Unit, RowIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    match state.phase {
      ComparePairs => {
        if state.left_row >= state.left_count {
          state.phase = FinishSearch
          continue
        }
        if state.right_row >= state.right_count {
          state.phase = EmitLeftRemainder
          continue
        }
        let left_row = state.left_row
        let right_row = state.right_row
        let keys_match = match (state.equal_keys)(left_row, right_row) {
          Ok(value) => value
          Err(issue) => return @bounded.Failed(issue, progress, used + 1)
        }
        let temporal_match = keys_match &&
          (if state.overlap {
            state.left_starts[left_row] < state.right_ends[right_row] &&
            state.right_starts[right_row] < state.left_ends[left_row]
          } else {
            state.right_starts[right_row] <= state.left_starts[left_row] &&
            state.left_starts[left_row] < state.right_ends[right_row]
          })
        if temporal_match {
          state.matched = true
          if state.kind == @join.Inner || state.kind == @join.Left {
            match (state.emit)(left_row, Some(right_row)) {
              Ok(_) => ()
              Err(issue) => return @bounded.Failed(issue, progress, used + 1)
            }
          }
        }
        state.right_row += 1
        used += 1
        progress += 1
      }
      EmitLeftRemainder => {
        let emit = (state.kind == @join.Left && !state.matched) ||
          (state.kind == @join.Semi && state.matched) ||
          (state.kind == @join.Anti && !state.matched)
        if emit {
          match (state.emit)(state.left_row, None) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used + 1)
          }
        }
        state.left_row += 1
        state.right_row = 0
        state.matched = false
        state.phase = ComparePairs
        used += 1
        progress += 1
      }
      FinishSearch => return @bounded.Complete((), progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn start_interval_search(
  control : @bounded.Control,
  left_count : Int,
  right_count : Int,
  kind : @join.Kind,
  overlap : Bool,
  left_starts : Array[Int64],
  left_ends : Array[Int64],
  right_starts : Array[Int64],
  right_ends : Array[Int64],
  equal_keys : (Int, Int) -> Result[Bool, RowIssue],
  emit : (Int, Int?) -> Result[Unit, RowIssue],
) -> IntervalSearchExecution {
  let state : IntervalSearchState = {
    left_count,
    right_count,
    kind,
    overlap,
    left_starts,
    left_ends,
    right_starts,
    right_ends,
    equal_keys,
    emit,
    phase: ComparePairs,
    left_row: 0,
    right_row: 0,
    matched: false,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    interval_search_step,
    _ => true,
    _ => true,
  )
  { session, token: Some(token), }
}

///|
fn advance_interval_search(
  value : IntervalSearchExecution,
  quantum : Int,
) -> Result[IntervalSearchPoll, RowIssue] {
  guard value.token is Some(token) else { return Err(InvalidRows) }
  match @bounded.advance(value.session, token, quantum) {
    Err(_) => Err(InvalidRows)
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(IntervalSearchContinue(progress~, work~))
    }
    Ok(@bounded.Completed(_, progress~, work~)) => {
      value.token = None
      Ok(IntervalSearchComplete(progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(IntervalSearchFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(IntervalSearchStopped(reason, progress~, work~))
    }
  }
}

///|
fn cleanup_interval_search(value : IntervalSearchExecution) -> Bool {
  @bounded.cleanup(value.session).unwrap_or(false)
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
    let search_control = @bounded.control()
    let search = start_interval_search(
      search_control,
      left_count,
      right_count,
      kind,
      overlap,
      left_starts,
      left_ends,
      right_starts,
      right_ends,
      fn(left_row, right_row) {
        if !spend_control(control, 1) {
          Err(RowLimit)
        } else {
          equal_keys(left_row, right_row)
        }
      },
      emit,
    )
    let mut searching = true
    while searching {
      match advance_interval_search(search, 1024) {
        Ok(IntervalSearchContinue(progress~, work~)) => {
          ignore(progress)
          ignore(work)
        }
        Ok(IntervalSearchComplete(progress~, work~)) => {
          ignore(progress)
          ignore(work)
          if !cleanup_interval_search(search) {
            return Err(InvalidRows)
          }
          searching = false
        }
        Ok(IntervalSearchFailed(issue, progress~, work~)) => {
          ignore(progress)
          ignore(work)
          cleanup_interval_search(search) |> ignore
          return Err(issue)
        }
        Ok(IntervalSearchStopped(reason, progress~, work~)) => {
          ignore(reason)
          ignore(progress)
          ignore(work)
          cleanup_interval_search(search) |> ignore
          return Err(InvalidRows)
        }
        Err(issue) => {
          cleanup_interval_search(search) |> ignore
          return Err(issue)
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
