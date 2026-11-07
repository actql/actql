///|
/// Exact admitted Common field values, without the provider's {value:...}
/// wrappers. This emits DATA only and invents neither defaults nor keys.
pub fn record_write_values_json(
  values : RecordWriteValues,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RecordWriteJsonIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    for (name, value) in values.originals {
      @encode.key(writer, name)
      @admitted.emit_checked_wire_value(value, writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}
