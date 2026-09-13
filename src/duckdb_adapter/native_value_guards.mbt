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
// Exact record byte length includes typed cells, field-name escaping and
// punctuation. Schema order suffices for length; receipt hashing independently
// uses canonical column order. No row object or second admission is needed.
fn measure_native_record(
  budget : NativeValueBudget,
  batch : PhysicalBatch,
  row : Int,
) -> Result[Unit, NativeValueIssue] {
  let usage = try {
    let writer = @encode.measuring_writer(
      budget.bytes,
      budget.nodes,
      budget.depth,
    )
    @encode.begin_object(writer)
    for column in 0..<batch.owner.mappings.length() {
      if budget.work == 0 {
        return Err(MeasurementWork)
      }
      budget.work -= 1
      @encode.key(
        writer,
        @schema.reference_name(
          @schema.field_at(batch.owner.schema, column).unwrap().name,
        ),
      )
      @admitted.emit_wire_value(
        physical_batch_cell(batch, row, column).unwrap().value,
        writer,
      )
    }
    @encode.end_object(writer)
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
      match measure_native_record(budget, batch, row) {
        Ok(_) => ()
        Err(issue) => return Err(Guard(port.role, global_row, -1, issue))
      }
      global_row += 1
    }
  }
  Ok(())
}
