///|
priv struct LogicalValueMeasure {
  wire_bytes : Int
  weight : Int64
}

///|
priv enum LogicalMeasureIssue {
  InvalidMeasureLimits
  LogicalWorkLimit
  HostMeasureLimit
  WireMeasureFailure
} derive(Eq, Debug)

///|
/// The work allowance bounds logical occurrences, not interpreter instructions.
/// Separate host limits bound traversal depth and wire measurement machinery.
fn measure_logical_value(
  value : Value,
  max_work : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[LogicalValueMeasure, LogicalMeasureIssue] {
  if max_work < 0L ||
    max_work > 9007199254740991L ||
    max_bytes < 0 ||
    max_nodes < 0 ||
    max_depth < 0 {
    return Err(InvalidMeasureLimits)
  }
  let mut remaining = max_work
  fn charge(n : Int64) -> Bool {
    if n < 0L || n > remaining {
      return false
    }
    remaining -= n
    true
  }
  fn text_weight(s : String) -> Bool {
    // Host strings and decoder lengths are Int-indexed. This bounded scan
    // allocates no UTF-8 copy and cannot charge beyond the remaining allowance.
    let cap = if remaining > 2147483647L {
      2147483647
    } else {
      remaining.to_int()
    }
    match @scalar.admit_utf8_length(s, cap) {
      Ok(n) => charge(n.to_int64())
      Err(_) => false
    }
  }
  let stack : Array[MeasureFrame] = []
  match value {
    Captured(v) => stack.push(Read(v, 1))
    Text(s) =>
      if !charge(1L) || !text_weight(s) {
        return Err(LogicalWorkLimit)
      }
    Null | Number(_) | Boolean(_) =>
      if !charge(1L) {
        return Err(LogicalWorkLimit)
      }
  }
  let mut nodes = 0
  while stack.pop() is Some(frame) {
    match frame {
      Read(v, depth) => {
        if depth > max_depth || nodes == max_nodes {
          return Err(HostMeasureLimit)
        }
        nodes += 1
        if !charge(1L) {
          return Err(LogicalWorkLimit)
        }
        match v {
          @admitted.Null | @admitted.Number(_) | @admitted.Boolean(_) => ()
          @admitted.Text(s) | @admitted.Date(s) | @admitted.Timestamp(s) =>
            if !text_weight(s) {
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
            if !charge(size) {
              return Err(LogicalWorkLimit)
            }
          }
          @admitted.Array(items) =>
            if @admitted.element_count(items) > 0 {
              if depth >= max_depth {
                return Err(HostMeasureLimit)
              }
              stack.push(ArrayNext(items, 0, depth + 1))
            }
          @admitted.Object(items) =>
            if @admitted.element_count(items) > 0 {
              if depth >= max_depth {
                return Err(HostMeasureLimit)
              }
              stack.push(ObjectNext(items, 0, depth + 1))
            }
          @admitted.Vector(items) => {
            let count = @admitted.element_count(items)
            if count > max_nodes - nodes || (count > 0 && depth >= max_depth) {
              return Err(HostMeasureLimit)
            }
            if !charge(count.to_int64()) {
              return Err(LogicalWorkLimit)
            }
            nodes += count
          }
        }
      }
      ArrayNext(items, i, depth) =>
        if @admitted.element_at(items, i) is Some(child) {
          if i + 1 < @admitted.element_count(items) {
            stack.push(ArrayNext(items, i + 1, depth))
          }
          stack.push(Read(child, depth))
        }
      ObjectNext(items, i, depth) =>
        if @admitted.element_at(items, i) is Some((key, child)) {
          if !text_weight(key) {
            return Err(LogicalWorkLimit)
          }
          if i + 1 < @admitted.element_count(items) {
            stack.push(ObjectNext(items, i + 1, depth))
          }
          stack.push(Read(child, depth))
        }
    }
  }
  let bytes = try {
    let writer = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
    match value {
      Null => @encode.null_value(writer)
      Number(n) => @encode.number_value(writer, n)
      Boolean(b) => @encode.bool_value(writer, b)
      Text(s) => @encode.string_value(writer, s)
      Captured(v) => @lower.emit_wire_value(v, writer)
    }
    @encode.finish_measurement(writer)
  } catch {
    _ => return Err(WireMeasureFailure)
  }
  Ok({ wire_bytes: bytes, weight: max_work - remaining, })
}
