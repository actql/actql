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
/// work weight and host node/depth limits, then one wire frame per advance
/// for the canonical byte size. `measure_logical_value` drains this state.
priv struct LogicalMeasureCursor {
  value : Value
  max_work : Int64
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  mut remaining : Int64
  stack : Array[MeasureFrame]
  mut nodes : Int
  mut writer : @encode.Writer?
  mut emit : @admitted.WireEmitCursor?
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
  // Host strings and decoder lengths are Int-indexed. This bounded scan
  // allocates no UTF-8 copy and cannot charge beyond the remaining allowance.
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
  if cursor.emit is Some(emit) {
    @admitted.cancel_wire_emit(emit)
  }
  cursor.emit = None
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
            if !logical_measure_text(cursor, @admitted.reference_wire(reference)) {
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
      match cursor.value {
        Captured(v) => {
          cursor.emit = Some(@admitted.start_wire_emit(v, writer))
          return Ok(None)
        }
        scalar =>
          emit_runtime_value(scalar, writer) catch {
            _ => return Err(WireMeasureFailure)
          }
      }
      writer
    }
  }
  if cursor.emit is Some(emit) {
    let finished = @admitted.advance_wire_emit(emit) catch {
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
  Ok(Some({ wire_bytes: bytes, weight: cursor.max_work - cursor.remaining }))
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
