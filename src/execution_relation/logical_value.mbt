///|
priv struct LogicalValueMeasure {
  wire_bytes : Int
  weight : Int64
}

///|
pub(all) enum LogicalMeasureIssue {
  InvalidMeasureLimits
  LogicalWorkLimit
  HostMeasureLimit
  WireMeasureFailure
  ReferenceUnavailable
} derive(Eq, Debug)

///|
/// Resumable logical measurement: one traversal frame per advance for the
/// work weight and host node/depth limits, with finite Text chunks, then one
/// wire frame per advance for canonical bytes. `measure_logical_value` drains
/// this state; bounded callers retain it instead of draining a whole cell.
priv struct LogicalMeasureCursor {
  value : Value
  max_work : Int64
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  mut remaining : Int64
  stack : Array[MeasureFrame]
  mut text : (String, Int)?
  mut nodes : Int
  mut writer : @encode.Writer?
  mut emit : IdentityWireCursor?
  mut done : Bool
}

///|
fn logical_measure_charge(cursor : LogicalMeasureCursor, n : Int64) -> Bool {
  if n < 0L || n > cursor.remaining {
    return false
  }
  cursor.remaining -= n
  true
}

///|
fn logical_measure_text(cursor : LogicalMeasureCursor, s : String) -> Bool {
  // Small strings retain their finite fast path. Long strings are borrowed
  // until their shared UTF-8 walk completes across subsequent advances.
  if s.length() > 64 {
    cursor.text = Some((s, 0))
    return true
  }
  let cap = if cursor.remaining > 2147483647L {
    2147483647
  } else {
    cursor.remaining.to_int()
  }
  match @scalar.admit_utf8_length(s, cap) {
    Ok(n) => logical_measure_charge(cursor, n.to_int64())
    Err(_) => false
  }
}

///|
fn start_logical_measure(
  value : Value,
  max_work : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LogicalMeasureCursor, LogicalMeasureIssue] {
  if max_work < 0L ||
    max_work > 9007199254740991L ||
    max_bytes < 0 ||
    max_nodes < 0 ||
    max_depth < 0 {
    return Err(InvalidMeasureLimits)
  }
  let cursor : LogicalMeasureCursor = {
    value,
    max_work,
    max_bytes,
    max_nodes,
    max_depth,
    remaining: max_work,
    stack: [],
    text: None,
    nodes: 0,
    writer: None,
    emit: None,
    done: false,
  }
  match value {
    Captured(v) => cursor.stack.push(Read(v, 1))
    Text(s) =>
      if !logical_measure_charge(cursor, 1L) || !logical_measure_text(cursor, s) {
        return Err(LogicalWorkLimit)
      }
    Null | Number(_) | Boolean(_) =>
      if !logical_measure_charge(cursor, 1L) {
        return Err(LogicalWorkLimit)
      }
  }
  Ok(cursor)
}

///|
/// Release every pending frame and wire state.
fn clear_logical_measure(cursor : LogicalMeasureCursor) -> Unit {
  cursor.stack.clear()
  cursor.text = None
  if cursor.emit is Some(emit) {
    cancel_identity_wire(emit)
  }
  cursor.emit = None
  if cursor.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  cursor.writer = None
  cursor.done = true
}

///|
fn advance_logical_measure(
  cursor : LogicalMeasureCursor,
) -> Result[LogicalValueMeasure?, LogicalMeasureIssue] {
  if cursor.done {
    return Err(InvalidMeasureLimits)
  }
  let result = advance_logical_measure_impl(cursor)
  match result {
    Ok(None) => ()
    Ok(Some(_)) | Err(_) => clear_logical_measure(cursor)
  }
  result
}

///|
fn advance_logical_measure_impl(
  cursor : LogicalMeasureCursor,
) -> Result[LogicalValueMeasure?, LogicalMeasureIssue] {
  if cursor.text is Some((text, index)) {
    guard step_bounded_text_measure(text, index, bytes => {
        logical_measure_charge(cursor, bytes.to_int64())
      })
      is Some(next) else {
      return Err(LogicalWorkLimit)
    }
    cursor.text = if next == text.length() { None } else { Some((text, next)) }
    return Ok(None)
  }
  // Traversal: one frame per advance.
  if cursor.stack.pop() is Some(frame) {
    match frame {
      Read(v, depth) => {
        if depth > cursor.max_depth || cursor.nodes == cursor.max_nodes {
          return Err(HostMeasureLimit)
        }
        cursor.nodes += 1
        if !logical_measure_charge(cursor, 1L) {
          return Err(LogicalWorkLimit)
        }
        match v {
          @admitted.JsonData(payload) => {
            cursor.nodes -= 1
            cursor.stack.push(Read(payload, depth))
          }
          @admitted.Null | @admitted.Number(_) | @admitted.Boolean(_) => ()
          @admitted.Text(s) | @admitted.Date(s) | @admitted.Timestamp(s) =>
            if !logical_measure_text(cursor, s) {
              return Err(LogicalWorkLimit)
            }
          @admitted.Decimal(d) => {
            let sign = if d.coefficient.has_prefix("-") { 1L } else { 0L }
            let digits = d.coefficient.length().to_int64() - sign
            let size = if d.scale == 0 {
              digits + sign
            } else {
              Int64::max(digits, d.scale.to_int64() + 1L) + sign + 1L
            }
            if !logical_measure_charge(cursor, size) {
              return Err(LogicalWorkLimit)
            }
          }
          @admitted.Array(items) =>
            if @admitted.element_count(items) > 0 {
              if depth >= cursor.max_depth {
                return Err(HostMeasureLimit)
              }
              cursor.stack.push(ArrayNext(items, 0, depth + 1))
            }
          @admitted.Object(items) =>
            if @admitted.element_count(items) > 0 {
              if depth >= cursor.max_depth {
                return Err(HostMeasureLimit)
              }
              cursor.stack.push(ObjectNext(items, 0, depth + 1))
            }
          @admitted.Vector(items) => {
            let count = @admitted.element_count(items)
            if count > cursor.max_nodes - cursor.nodes ||
              (count > 0 && depth >= cursor.max_depth) {
              return Err(HostMeasureLimit)
            }
            if !logical_measure_charge(cursor, count.to_int64()) {
              return Err(LogicalWorkLimit)
            }
            cursor.nodes += count
          }
          @admitted.Reference(reference) => {
            if !@admitted.reference_available(reference) {
              return Err(ReferenceUnavailable)
            }
            if !logical_measure_text(
                cursor,
                @admitted.reference_wire(reference),
              ) {
              return Err(LogicalWorkLimit)
            }
          }
        }
      }
      ArrayNext(items, i, depth) =>
        if @admitted.element_at(items, i) is Some(child) {
          if i + 1 < @admitted.element_count(items) {
            cursor.stack.push(ArrayNext(items, i + 1, depth))
          }
          cursor.stack.push(Read(child, depth))
        }
      ObjectNext(items, i, depth) =>
        if @admitted.element_at(items, i) is Some((key, child)) {
          if !logical_measure_text(cursor, key) {
            return Err(LogicalWorkLimit)
          }
          if i + 1 < @admitted.element_count(items) {
            cursor.stack.push(ObjectNext(items, i + 1, depth))
          }
          cursor.stack.push(Read(child, depth))
        }
    }
    return Ok(None)
  }
  // Wire size: one emitted frame per advance.
  let writer = match cursor.writer {
    Some(writer) => writer
    None => {
      let writer = @encode.measuring_writer(
        cursor.max_bytes,
        cursor.max_nodes,
        cursor.max_depth,
      ) catch {
        _ => return Err(WireMeasureFailure)
      }
      cursor.writer = Some(writer)
      if cursor.value is Captured(_) ||
        (cursor.value is Text(text) && text.length() > 64) {
        cursor.emit = Some(
          identity_scan_emit(cursor.value, writer) catch {
            _ => return Err(WireMeasureFailure)
          },
        )
        return Ok(None)
      }
      emit_runtime_value(cursor.value, writer) catch {
        _ => return Err(WireMeasureFailure)
      }
      writer
    }
  }
  if cursor.emit is Some(emit) {
    let finished = advance_identity_wire(emit) catch {
      _ => return Err(WireMeasureFailure)
    }
    if !finished {
      return Ok(None)
    }
    cursor.emit = None
  }
  let bytes = @encode.finish_measurement(writer) catch {
    _ => return Err(WireMeasureFailure)
  }
  Ok(Some({ wire_bytes: bytes, weight: cursor.max_work - cursor.remaining, }))
}

///|
/// The work allowance bounds logical occurrences, not interpreter instructions.
/// Separate host limits bound traversal depth and wire measurement machinery.
/// Drains the resumable `LogicalMeasureCursor`.
fn measure_logical_value(
  value : Value,
  max_work : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LogicalValueMeasure, LogicalMeasureIssue] {
  let cursor = match
    start_logical_measure(value, max_work, max_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_logical_measure(cursor) {
      Ok(None) => ()
      Ok(Some(measure)) => break Ok(measure)
      Err(issue) => break Err(issue)
    }
  } nobreak {
    Err(InvalidMeasureLimits)
  }
}
