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
/// paid one unit per advance. Sizing and exact-capacity construction also yield
/// between scalars, without a final whole-input join or a second byte charge.
priv struct AggregateString {
  values : Array[Value]
  delimiter : String
  mut delimiter_bytes : Int64
  maximum : Int64
  control : ControlBudget
  workspace : RowWorkspace
  mut builder : StringBuilder?
  mut pending : Int64
  mut bytes : Int64
  mut units : Int64
  mut allocated : Int
  mut offset : Int
  mut emitted : Int
  mut separator : Bool
  mut total : Int64
  mut index : Int
  mut phase : Int
  mut closed : Bool
}

///|
fn start_aggregate_string(
  values : Array[Value],
  delimiter : String,
  maximum : Int64,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[AggregateString, RowIssue] {
  if !reserve_slots(workspace, 2) {
    return Err(RowLimit)
  }
  Ok({
    values,
    delimiter,
    delimiter_bytes: 0L,
    maximum,
    control,
    workspace,
    builder: None,
    pending: 0L,
    bytes: 0L,
    units: 0L,
    allocated: 0,
    offset: 0,
    emitted: 0,
    separator: false,
    total: 0L,
    index: 0,
    phase: 0,
    closed: false,
  })
}

///|
fn close_aggregate_string(state : AggregateString) -> Unit {
  if state.closed {
    return
  }
  state.builder = None
  release_slots(state.workspace, state.allocated + 2)
  state.allocated = 0
  state.closed = true
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
    Err(_) => close_aggregate_string(state)
    Ok(Some(_)) => state.closed = true
    Ok(None) => ()
  }
  result
}

///|
fn advance_aggregate_string_impl(
  s : AggregateString,
) -> Result[Value?, RowIssue] {
  match s.phase {
    // Delimiters are undemanded for zero/singleton contributors.
    0 => {
      if s.values.length() <= 1 {
        s.phase = 1
        return Ok(None)
      }
      if s.maximum < 0 || s.delimiter.length().to_int64() > s.maximum {
        return Err(RowLimit)
      }
      if s.offset < s.delimiter.length() {
        guard text_function_scalar(s.delimiter, s.offset)
          is Some((_, next, width, _)) &&
          width.to_int64() <= s.maximum - s.delimiter_bytes else {
          return Err(RowLimit)
        }
        s.delimiter_bytes += width.to_int64()
        s.offset = next
        return Ok(None)
      }
      s.offset = 0
      s.phase = 1
      Ok(None)
    }
    1 => {
      if s.index >= s.values.length() {
        s.phase = 4
        return Ok(None)
      }
      guard s.values[s.index] is Text(text) else { return Err(InvalidRows) }
      if s.maximum < 0 || text.length().to_int64() > s.maximum {
        return Err(RowLimit)
      }
      s.offset = 0
      s.bytes = 0L
      s.phase = 2
      Ok(None)
    }
    2 => {
      guard s.values[s.index] is Text(text) else { return Err(InvalidRows) }
      if s.offset < text.length() {
        guard text_function_scalar(text, s.offset) is Some((_, next, width, _)) &&
          width.to_int64() <= s.maximum - s.bytes else {
          return Err(RowLimit)
        }
        s.bytes += width.to_int64()
        s.offset = next
        return Ok(None)
      }
      let separator = if s.index == 0 { 0L } else { s.delimiter_bytes }
      if separator > s.maximum - s.total ||
        s.bytes > s.maximum - s.total - separator ||
        separator > s.control.remaining.to_int64() {
        return Err(RowLimit)
      }
      s.pending = separator + s.bytes
      s.total += s.pending
      s.units += text.length().to_int64() +
        (if s.index == 0 { 0L } else { s.delimiter.length().to_int64() })
      s.phase = 3
      Ok(None)
    }
    3 => {
      if s.pending > 0L {
        if !spend_control(s.control, 1) {
          return Err(RowLimit)
        }
        s.pending -= 1L
        return Ok(None)
      }
      s.index += 1
      s.phase = 1
      Ok(None)
    }
    4 => {
      // The pinned Native builder takes a byte-sized Int hint. Reject physical
      // capacity overflow before allocation, not by narrowing the String type.
      if s.units > 1073741823L {
        return Err(RowLimit)
      }
      let allocated = Int::max(1, s.units.to_int())
      if !reserve_slots(s.workspace, allocated) {
        return Err(RowLimit)
      }
      s.allocated = allocated
      s.builder = Some(StringBuilder(size_hint=s.units.to_int() * 2))
      s.index = 0
      s.offset = 0
      s.separator = false
      s.phase = 5
      Ok(None)
    }
    5 => {
      guard s.builder is Some(builder) else { return Err(InvalidRows) }
      if s.index >= s.values.length() {
        if s.emitted.to_int64() != s.units {
          return Err(InvalidRows)
        }
        let value = builder.to_string()
        s.builder = None
        // The completed buffer goes to the enclosing row scope. Only temporary
        // state/builder handles are returned here; stop cannot revoke output.
        if s.units == 0L {
          release_slots(s.workspace, s.allocated)
        }
        s.allocated = 0
        release_slots(s.workspace, 2)
        return Ok(Some(Text(value)))
      }
      let text = if s.separator {
        s.delimiter
      } else {
        guard s.values[s.index] is Text(text) else { return Err(InvalidRows) }
        text
      }
      if s.offset == text.length() {
        if s.separator {
          s.separator = false
        } else {
          s.index += 1
          s.separator = true
        }
        s.offset = 0
        return Ok(None)
      }
      guard text_function_scalar(text, s.offset) is Some((scalar, next, _, _)) &&
        next - s.offset <= s.allocated - s.emitted else {
        return Err(RowLimit)
      }
      builder.write_char(scalar)
      s.emitted += next - s.offset
      s.offset = next
      Ok(None)
    }
    _ => Err(InvalidRows)
  }
}
