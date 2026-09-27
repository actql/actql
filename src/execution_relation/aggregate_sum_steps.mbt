///|
/// Add Decimal `sum` contributors with at most one control unit per advance.
/// Each addition charges the running and contributor coefficients by UTF-8
/// byte and its digit capacity by unit, as `add_decimal_coefficients` does,
/// before the uncharged digit arithmetic runs in one bounded advance.
priv struct AggregateDecimalSum {
  values : Array[Value]
  precision : Int
  scale : Int
  control : ControlBudget
  workspace : RowWorkspace
  mut index : Int
  mut coefficient : String
  mut phase : Int
  mut pending : Int
  mut contributor : String
  mut closed : Bool
}

///|
fn start_aggregate_decimal_sum(
  values : Array[Value],
  precision : Int,
  scale : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> AggregateDecimalSum {
  {
    values,
    precision,
    scale,
    control,
    workspace,
    index: 0,
    coefficient: "0",
    phase: 0,
    pending: 0,
    contributor: "",
    closed: false,
  }
}

///|
fn close_aggregate_decimal_sum(state : AggregateDecimalSum) -> Unit {
  state.closed = true
}

///|
fn decimal_sum_capacity(left : String, right : String) -> Int {
  let left_count = left.length() - (if left[0] == '-' { 1 } else { 0 })
  let right_count = right.length() - (if right[0] == '-' { 1 } else { 0 })
  Int::max(left_count, right_count) + 1
}

///|
fn advance_aggregate_decimal_sum(
  state : AggregateDecimalSum,
) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_decimal_sum_impl(state)
  match result {
    Err(_) | Ok(Some(_)) => close_aggregate_decimal_sum(state)
    Ok(None) => ()
  }
  result
}

///|
fn advance_aggregate_decimal_sum_impl(
  s : AggregateDecimalSum,
) -> Result[Value?, RowIssue] {
  match s.phase {
    // Select the next contributor, or finish.
    0 => {
      if s.index >= s.values.length() {
        return match
          @admitted.decimal_from_coefficient(
            s.coefficient,
            s.precision,
            s.scale,
          ) {
          Some(value) => Ok(Some(Captured(value)))
          None => Err(Aggregation(ArithmeticFailure))
        }
      }
      guard s.values[s.index] is Captured(@admitted.Decimal(decimal)) &&
        decimal.scale == s.scale else {
        return Err(InvalidRows)
      }
      s.contributor = decimal.coefficient
      s.pending = match @scalar.admit_utf8_length(s.coefficient, 2147483647) {
        Ok(bytes) => bytes
        Err(_) => return Err(RowLimit)
      }
      s.phase = 1
      Ok(None)
    }
    // Charge the running coefficient.
    1 => {
      if s.pending > 0 {
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        s.pending -= 1
        return Ok(None)
      }
      s.pending = match @scalar.admit_utf8_length(s.contributor, 2147483647) {
        Ok(bytes) => bytes
        Err(_) => return Err(RowLimit)
      }
      s.phase = 2
      Ok(None)
    }
    // Charge the contributor coefficient.
    2 => {
      if s.pending > 0 {
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        s.pending -= 1
        return Ok(None)
      }
      s.pending = decimal_sum_capacity(s.coefficient, s.contributor)
      s.phase = 3
      Ok(None)
    }
    // Charge the digit capacity.
    3 => {
      if s.pending > 0 {
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        s.pending -= 1
        return Ok(None)
      }
      s.phase = 4
      Ok(None)
    }
    // Digit arithmetic, already charged; a free budget avoids re-charging.
    _ => {
      let charged : ControlBudget = {
        remaining: 2147483647,
        max_frames: s.control.max_frames,
      }
      s.coefficient = match
        add_decimal_coefficients(
          s.coefficient,
          s.contributor,
          charged,
          s.workspace,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      s.index += 1
      s.phase = 0
      Ok(None)
    }
  }
}

///|
/// Select the first or last non-null contributor in the aggregate's order.
/// The member order uses the resumable stable merge; the scan advances one
/// charged position at a time.
priv struct AggregateEndpoint[T] {
  members : AggregateRangeRows[T]
  column : Int
  first : Bool
  control : ControlBudget
  order : StableOrderExecution[AggregateRangeRows[T]]
  mut ordered : Array[Int]?
  mut offset : Int
  mut closed : Bool
}

///|
fn[T : IndexedRows] start_aggregate_endpoint(
  members : AggregateRangeRows[T],
  order : Array[ColumnOrder],
  column : Int,
  first : Bool,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> AggregateEndpoint[T] {
  {
    members,
    column,
    first,
    control,
    order: start_stable_order(members, order, control, workspace),
    ordered: None,
    offset: 0,
    closed: false,
  }
}

///|
fn[T] close_aggregate_endpoint(state : AggregateEndpoint[T]) -> Unit {
  if state.closed {
    return
  }
  close_stable_order(state.order)
  state.closed = true
}

///|
fn[T : IndexedRows] advance_aggregate_endpoint(
  state : AggregateEndpoint[T],
) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let ordered = match state.ordered {
    Some(value) => value
    None =>
      match advance_stable_order(state.order) {
        Ok(None) => return Ok(None)
        Ok(Some(value)) => {
          state.ordered = Some(value)
          return Ok(None)
        }
        Err(issue) => {
          close_aggregate_endpoint(state)
          return Err(ordering_row_issue(issue))
        }
      }
  }
  if state.offset >= ordered.length() {
    state.closed = true
    return Ok(Some(Null))
  }
  if !spend_control(state.control, 1) {
    close_aggregate_endpoint(state)
    return Err(RowLimit)
  }
  let position = if state.first {
    state.offset
  } else {
    ordered.length() - state.offset - 1
  }
  state.offset += 1
  let value = IndexedRows::read_cell(
    state.members,
    ordered[position],
    state.column,
  )
  if value is Null {
    return Ok(None)
  }
  state.closed = true
  Ok(Some(value))
}
