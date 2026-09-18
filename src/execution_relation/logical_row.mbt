///|
fn emit_runtime_value(
  value : Value,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match value {
    Null => @encode.null_value(writer)
    Number(n) => @encode.number_value(writer, n)
    Boolean(b) => @encode.bool_value(writer, b)
    Text(s) => @encode.string_value(writer, s)
    Captured(v) => @admitted.emit_wire_value(v, writer)
  }
}

///|
/// Measure a complete retained row, including its object and field names.
/// Names are already validated unique by the row layout, never reinterpreted.
fn[T : RowValues] charge_logical_row(
  b : LogicalBudget,
  names : Array[String],
  row : T,
) -> Result[LogicalValueMeasure, LogicalBudgetIssue] {
  if b.failed {
    return Err(FailedLogicalBudget)
  }
  if names.length() != row.value_count() || b.host_depth < 1 || b.host_nodes < 1 {
    b.failed = true
    return Err(ValueMeasure(HostMeasureLimit))
  }
  let mut remaining = b.limits.max_work - b.work
  if remaining == 0L {
    b.failed = true
    return Err(WorkLimit)
  }
  remaining -= 1L
  let cap = Int64::min(b.limits.max_value_bytes, b.host_bytes.to_int64()).to_int()
  let bytes = try {
    let writer = @encode.measuring_writer(cap, b.host_nodes, b.host_depth)
    @encode.begin_object(writer)
    for i = 0; i < names.length(); i = i + 1 {
      if i >= b.host_nodes - 1 {
        b.failed = true
        return Err(ValueMeasure(HostMeasureLimit))
      }
      let key_cap = Int64::min(remaining, 2147483647L).to_int()
      let key_bytes = match @scalar.admit_utf8_length(names[i], key_cap) {
        Ok(n) => n
        Err(_) => {
          b.failed = true
          return Err(WorkLimit)
        }
      }
      remaining -= key_bytes.to_int64()
      let m = match
        measure_logical_value(
          row.value_at(i),
          remaining,
          cap,
          b.host_nodes - 1,
          b.host_depth - 1,
        ) {
        Ok(m) => m
        Err(e) => {
          b.failed = true
          return Err(ValueMeasure(e))
        }
      }
      remaining -= m.weight
      @encode.key(writer, names[i])
      emit_runtime_value(row.value_at(i), writer)
    }
    @encode.end_object(writer)
    @encode.finish_measurement(writer)
  } catch {
    _ => {
      b.failed = true
      return Err(ValueMeasure(WireMeasureFailure))
    }
  }
  let weight = b.limits.max_work - b.work - remaining
  b.work += weight
  Ok({ wire_bytes: bytes, weight, })
}

///|
fn[T : RowValues] retain_logical_row(
  b : LogicalBudget,
  names : Array[String],
  row : T,
) -> Result[LogicalRoot, LogicalBudgetIssue] {
  let m = match charge_logical_row(b, names, row) {
    Ok(m) => m
    Err(e) => return Err(e)
  }
  reserve_logical_bytes(b, m.wire_bytes.to_int64())
}
