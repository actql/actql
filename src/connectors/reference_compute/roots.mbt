///|
priv struct RootBudget {
  ceiling : Int
  depth : Int
  mut work : Int
  mut bytes : Int
  mut nodes : Int
}

///|
fn measure_root(
  budget : RootBudget,
  row : Int,
  position : Int,
  value : @execution.Value,
) -> Result[Unit, PlanIssue] {
  if budget.work <= 0 {
    return Err(RootWorkLimit(row, position))
  }
  budget.work -= 1
  let usage = try {
    let writer = @encode.measuring_writer(
      budget.bytes,
      budget.nodes,
      budget.depth,
    )
    match value {
      Null => @encode.null_value(writer)
      Number(value) => @encode.number_value(writer, value)
      Boolean(value) => @encode.bool_value(writer, value)
      Text(value) => @encode.string_value(writer, value)
      Captured(value) => @admitted.emit_wire_value(value, writer)
    }
    @encode.finish_measurement_usage(writer)
  } catch {
    issue => return Err(RootMeasurement(row, position, issue))
  }
  budget.bytes -= usage.0
  budget.nodes -= usage.1
  if usage.0 > budget.ceiling {
    return Err(RootValueBytes(row, position))
  }
  Ok(())
}
