///|
/// Units already decided by an atomic charge, paid one per advance.
priv struct PendingUnits {
  mut remaining : Int
}

///|
/// Pay one pending unit. Returns true once nothing remains.
fn pay_pending_unit(
  pending : PendingUnits,
  control : ControlBudget,
) -> Result[Bool, RowIssue] {
  if pending.remaining <= 0 {
    return Ok(true)
  }
  if !spend_control(control, 1) {
    return Err(RowLimit)
  }
  pending.remaining -= 1
  Ok(pending.remaining == 0)
}

///|
fn utf8_units(text : String) -> Result[Int, RowIssue] {
  match @scalar.admit_utf8_length(text, 2147483647) {
    Ok(bytes) => Ok(bytes)
    Err(_) => Err(RowLimit)
  }
}

///|
/// Collect the non-null argument values of one group in aggregate order.
/// Member ordering uses the resumable stable merge; the scan charges one
/// position per advance, as `ordered_aggregate_values` does.
priv struct AggregateOrderedValues[T] {
  members : AggregateRangeRows[T]
  column : Int
  control : ControlBudget
  workspace : RowWorkspace
  order : StableOrderExecution[AggregateRangeRows[T]]
  values : Array[Value]
  mut ordered : Array[Int]?
  mut position : Int
  mut closed : Bool
}

///|
fn[T : IndexedRows] start_aggregate_ordered_values(
  members : AggregateRangeRows[T],
  order : Array[ColumnOrder],
  column : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> AggregateOrderedValues[T] {
  {
    members,
    column,
    control,
    workspace,
    order: start_stable_order(members, order, control, workspace),
    values: [],
    ordered: None,
    position: 0,
    closed: false,
  }
}

///|
fn[T] close_aggregate_ordered_values(state : AggregateOrderedValues[T]) -> Unit {
  if state.closed {
    return
  }
  close_stable_order(state.order)
  state.closed = true
}

///|
fn[T : IndexedRows] advance_aggregate_ordered_values(
  state : AggregateOrderedValues[T],
) -> Result[Array[Value]?, RowIssue] {
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
          close_aggregate_ordered_values(state)
          return Err(ordering_row_issue(issue))
        }
      }
  }
  if state.position >= ordered.length() {
    state.closed = true
    return Ok(Some(state.values))
  }
  if !spend_control(state.control, 1) {
    close_aggregate_ordered_values(state)
    return Err(RowLimit)
  }
  let value = IndexedRows::read_cell(
    state.members,
    ordered[state.position],
    state.column,
  )
  state.position += 1
  if !(value is Null) {
    if !reserve_slots(state.workspace, 1) {
      close_aggregate_ordered_values(state)
      return Err(RowLimit)
    }
    state.values.push(value)
  }
  Ok(None)
}

///|
/// Remove duplicate contributors in first-occurrence order with the charges
/// of `distinct_aggregate_values`: one unit per value, the identity bytes,
/// the new bucket's CID text, and the bucket comparisons.
priv struct AggregateDistinct {
  values : Array[Value]
  control : ControlBudget
  workspace : RowWorkspace
  identity_limits : ValueLimits
  buckets : Map[String, Array[Value]]
  output : Array[Value]
  pending : PendingUnits
  comparison : BoundedCompleteValueComparison
  mut index : Int
  mut phase : Int
  mut cid : String
  mut bucket : Array[Value]
  mut candidate : Int
  mut closed : Bool
}

///|
fn start_aggregate_distinct(
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
  identity_limits : ValueLimits,
) -> AggregateDistinct {
  {
    values,
    control,
    workspace,
    identity_limits,
    buckets: Map([]),
    output: [],
    pending: { remaining: 0, },
    comparison: bounded_complete_value_comparison(),
    index: 0,
    phase: 0,
    cid: "",
    bucket: [],
    candidate: 0,
    closed: false,
  }
}

///|
fn advance_aggregate_distinct(
  state : AggregateDistinct,
) -> Result[Array[Value]?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_distinct_impl(state)
  match result {
    Err(_) | Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}

///|
fn advance_aggregate_distinct_impl(
  s : AggregateDistinct,
) -> Result[Array[Value]?, RowIssue] {
  match s.phase {
    // One unit per contributor, then its identity.
    0 => {
      if s.index >= s.values.length() {
        return Ok(Some(s.output))
      }
      if !spend_control(s.control, 1) {
        return Err(RowLimit)
      }
      let (cid, bytes) = match
        runtime_value_identity_usage(
          s.values[s.index],
          s.control,
          s.workspace,
          s.identity_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      s.cid = cid
      s.pending.remaining = bytes
      s.phase = 1
      Ok(None)
    }
    // Identity bytes, then the bucket.
    1 =>
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          match s.buckets.get(s.cid) {
            Some(bucket) => {
              s.bucket = bucket
              s.candidate = 0
              s.phase = 3
            }
            None => {
              if !reserve_slots(s.workspace, 1) {
                return Err(RowLimit)
              }
              s.pending.remaining = match utf8_units(s.cid) {
                Ok(bytes) => bytes
                Err(issue) => return Err(issue)
              }
              s.phase = 2
            }
          }
          Ok(None)
        }
      }
    // A new bucket's CID text.
    2 =>
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          let bucket : Array[Value] = []
          s.buckets[s.cid] = bucket
          s.bucket = bucket
          s.candidate = 0
          s.phase = 3
          Ok(None)
        }
      }
    // Compare with the bucket's retained values until a duplicate.
    3 => {
      if s.candidate < s.bucket.length() {
        match
          bounded_complete_value_comparison_step(
            s.comparison,
            s.bucket[s.candidate],
            s.values[s.index],
            s.control,
          ) {
          Err(issue) => return Err(ordering_row_issue(issue))
          Ok(None) => return Ok(None)
          Ok(Some(0)) => {
            s.index += 1
            s.phase = 0
            return Ok(None)
          }
          Ok(Some(_)) => {
            s.candidate += 1
            return Ok(None)
          }
        }
      }
      if !reserve_slots(s.workspace, 2) {
        return Err(RowLimit)
      }
      s.bucket.push(s.values[s.index])
      s.output.push(s.values[s.index])
      s.index += 1
      s.phase = 0
      Ok(None)
    }
    _ => Err(InvalidRows)
  }
}

///|
/// Build an `array_agg` value with the charges of `evaluate_array_aggregate`:
/// one unit per item, then each row Text item's UTF-8 bytes before its
/// admission. Long row Text uses the shared resumed Value owner. The existing
/// ArrayBuilder transfers its complete backing instead of copying all items.
priv struct AggregateArray {
  values : Array[Value]
  control : ControlBudget
  workspace : RowWorkspace
  mut builder : @admitted.ArrayBuilder?
  mut text : RawTextAdmission?
  mut reserved : Int
  pending : PendingUnits
  mut phase : Int
  mut index : Int
  mut closed : Bool
}

///|
fn start_aggregate_array(
  values : Array[Value],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> AggregateArray {
  {
    values,
    control,
    workspace,
    builder: None,
    text: None,
    reserved: 0,
    pending: { remaining: values.length(), },
    phase: 0,
    index: 0,
    closed: false,
  }
}

///|
fn close_aggregate_array(state : AggregateArray) -> Unit {
  if state.closed {
    return
  }
  if state.text is Some(text) {
    close_raw_text_admission(text)
  }
  state.text = None
  if state.builder is Some(builder) {
    @admitted.cancel_array_value(builder) |> ignore
  }
  state.builder = None
  release_slots(state.workspace, state.reserved)
  state.reserved = 0
  state.closed = true
}

///|
fn advance_aggregate_array(state : AggregateArray) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_array_impl(state)
  match result {
    Err(_) => close_aggregate_array(state)
    Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}

///|
fn advance_aggregate_array_impl(s : AggregateArray) -> Result[Value?, RowIssue] {
  match s.phase {
    // One unit per item, then the item reservation.
    0 =>
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          if s.values.length() == 2147483647 ||
            !reserve_slots(s.workspace, s.values.length() + 1) {
            return Err(RowLimit)
          }
          s.reserved = s.values.length() + 1
          s.builder = @admitted.prepare_array_value(s.values.length())
          if s.builder is None {
            return Err(InvalidRows)
          }
          s.phase = 1
          Ok(None)
        }
      }
    // Admit the next item; row Text first pays its UTF-8 bytes.
    1 => {
      if s.index >= s.values.length() {
        guard s.builder is Some(builder) &&
          @admitted.finish_array_value(builder) is Some(value) else {
          return Err(InvalidRows)
        }
        s.builder = None
        // Item reservations pass with the completed value to its enclosing
        // row scope. Only the temporary builder handle is released here.
        release_slots(s.workspace, 1)
        s.reserved = 0
        return Ok(Some(Captured(value)))
      }
      match s.values[s.index] {
        Null => Err(InvalidRows)
        Text(text) => {
          if text.length() > 64 {
            s.text = match start_raw_text_admission(text, s.workspace) {
              Ok(state) => Some(state)
              Err(issue) => return Err(issue)
            }
            s.phase = 3
            return Ok(None)
          }
          s.pending.remaining = match utf8_units(text) {
            Ok(bytes) => bytes
            Err(issue) => return Err(issue)
          }
          s.phase = 2
          Ok(None)
        }
        value => {
          let free : ControlBudget = { remaining: 0, max_frames: 0, }
          match admitted_aggregate_item(value, free) {
            Ok(Some(item)) =>
              if !@admitted.append_array_item(s.builder.unwrap(), item) {
                return Err(InvalidRows)
              }
            Ok(None) => return Err(InvalidRows)
            Err(issue) => return Err(issue)
          }
          s.index += 1
          Ok(None)
        }
      }
    }
    2 =>
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          guard s.values[s.index] is Text(text) else { return Err(InvalidRows) }
          match @admitted.text_value(text, 2147483647) {
            Some(item) =>
              if !@admitted.append_array_item(s.builder.unwrap(), item) {
                return Err(InvalidRows)
              }
            None => return Err(InvalidRows)
          }
          s.index += 1
          s.phase = 1
          Ok(None)
        }
      }
    3 => {
      guard s.text is Some(text) else { return Err(InvalidRows) }
      match advance_raw_text_admission(text, s.control) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(None)
        Ok(Some(item)) => {
          if !@admitted.append_array_item(s.builder.unwrap(), item) {
            return Err(InvalidRows)
          }
          s.text = None
          s.index += 1
          s.phase = 1
          Ok(None)
        }
      }
    }
    _ => Err(InvalidRows)
  }
}

///|
/// Build a `string_agg` value with the checks and charges of
/// `evaluate_string_aggregate`: each separator and item's UTF-8 bytes are
/// paid one unit per advance. The final join is bounded by the output limit.
priv struct AggregateString {
  values : Array[Value]
  delimiter : String
  delimiter_bytes : Int64
  maximum : Int64
  control : ControlBudget
  strings : Array[String]
  pending : PendingUnits
  mut total : Int64
  mut index : Int
  mut phase : Int
  mut closed : Bool
}

///|
fn start_aggregate_string(
  values : Array[Value],
  delimiter : String,
  delimiter_bytes : Int64,
  maximum : Int64,
  control : ControlBudget,
) -> AggregateString {
  {
    values,
    delimiter,
    delimiter_bytes,
    maximum,
    control,
    strings: [],
    pending: { remaining: 0, },
    total: 0L,
    index: 0,
    phase: 0,
    closed: false,
  }
}

///|
fn advance_aggregate_string(
  state : AggregateString,
) -> Result[Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  let result = advance_aggregate_string_impl(state)
  match result {
    Err(_) | Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}

///|
fn advance_aggregate_string_impl(
  s : AggregateString,
) -> Result[Value?, RowIssue] {
  match s.phase {
    0 => {
      if s.index >= s.values.length() {
        return Ok(Some(Text(s.strings.join(s.delimiter))))
      }
      guard s.values[s.index] is Text(text) else { return Err(InvalidRows) }
      let bytes = match @scalar.admit_utf8_length64(text, s.maximum) {
        Ok(bytes) => bytes
        Err(_) => return Err(RowLimit)
      }
      let separator = if s.index == 0 { 0L } else { s.delimiter_bytes }
      if separator > s.maximum - s.total ||
        bytes > s.maximum - s.total - separator ||
        separator > s.control.remaining.to_int64() {
        return Err(RowLimit)
      }
      s.pending.remaining = (separator + bytes).to_int()
      s.total += separator + bytes
      s.phase = 1
      Ok(None)
    }
    _ =>
      match pay_pending_unit(s.pending, s.control) {
        Err(issue) => Err(issue)
        Ok(false) => Ok(None)
        Ok(true) => {
          guard s.values[s.index] is Text(text) else { return Err(InvalidRows) }
          s.strings.push(text)
          s.index += 1
          s.phase = 0
          Ok(None)
        }
      }
  }
}
