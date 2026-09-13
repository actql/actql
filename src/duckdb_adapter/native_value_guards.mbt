///|
pub(all) struct NativeValueGuards {
  max_value_bytes : Int
  max_output_rows : Int
}

///|
pub(all) enum NativeValueIssue {
  MeasurementWork
  Measurement(@encode.EncodeFailure)
  ValueBytes
  OutputRows
}

///|
/// One physical measurement ledger spans both receipts. It is not evaluator
/// logical work, receipt transport bytes, or a credit for input admission.
priv struct NativeValueBudget {
  guards : NativeValueGuards
  mut work : Int
  mut bytes : Int
  mut nodes : Int
  depth : Int
}

///|
fn measure_native_value(
  budget : NativeValueBudget,
  value : @admitted.CheckedValue,
) -> Result[Unit, NativeValueIssue] {
  if budget.work == 0 {
    return Err(MeasurementWork)
  }
  budget.work -= 1
  let usage = try {
    let writer = @encode.measuring_writer(
      budget.bytes,
      budget.nodes,
      budget.depth,
    )
    @admitted.emit_wire_value(value.value, writer)
    @encode.finish_measurement_usage(writer)
  } catch {
    issue => return Err(Measurement(issue))
  }
  budget.bytes -= usage.0
  budget.nodes -= usage.1
  if usage.0 > budget.guards.max_value_bytes {
    return Err(ValueBytes)
  }
  Ok(())
}

///|
/// Match the fixed-input path: finish admission before value measurement.
/// Read retained admitted values without copying or repeating admission.
fn measure_native_receipt(
  receiving : NativeReceiving,
  port : NativeReceiptPort,
) -> Result[Unit, NativeReceivingIssue] {
  let budget = receiving.measurement
  if port.role == NativeResult &&
    port.result.rows > budget.guards.max_output_rows {
    return Err(Guard(port.role, budget.guards.max_output_rows, -1, OutputRows))
  }
  let batches = match port.role {
    ValidationScan => receiving.validation_batches
    NativeResult => receiving.native_batches
  }
  let mut global_row = 0
  for batch in batches {
    for row in 0..<batch.rows {
      if budget.work == 0 {
        return Err(Guard(port.role, global_row, -1, MeasurementWork))
      }
      budget.work -= 1
      for column in 0..<port.result.mappings.length() {
        match
          measure_native_value(
            budget,
            physical_batch_cell(batch, row, column).unwrap(),
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Guard(port.role, global_row, column, issue))
        }
      }
      global_row += 1
    }
  }
  Ok(())
}
