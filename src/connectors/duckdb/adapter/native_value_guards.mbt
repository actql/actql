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
/// A successfully encoded canonical output row has the same keys and values as
/// the schema-order record measurement. Key order changes neither byte length
/// nor node count. The enclosing output array adds one depth level and, after
/// the first row, one comma byte. Near any guard boundary, use the original
/// ordered measurement to preserve its exact first error and partial charge.
fn charge_native_encoded_record(
  budget : NativeValueBudget,
  width : Int,
  previous : (Int, Int, Int),
  current : (Int, Int, Int),
  comma : Bool,
) -> Bool {
  let record_bytes = current.0 - previous.0 - (if comma { 1 } else { 0 })
  let record_nodes = current.1 - previous.1
  if width < 0 ||
    width >= budget.work ||
    record_bytes < 0 ||
    record_nodes < 0 ||
    record_bytes > budget.bytes ||
    record_nodes > budget.nodes ||
    record_bytes > budget.guards.max_value_bytes ||
    current.2 - 1 > budget.depth {
    return false
  }
  budget.work -= width + 1
  budget.bytes -= record_bytes
  budget.nodes -= record_nodes
  true
}

///|
/// Match the fixed-input path: finish admission before value measurement.
/// Read retained admitted values without copying or repeating admission.
fn measure_native_receipt(
  receiving : NativeReceiving,
  port : NativeReceiptPort,
) -> Result[Unit, NativeReceivingIssue] {
  let budget = receiving.measurement
  if port.role == ValidationScan && receiving.validation_stream is Some(stream) {
    return match stream.guard_issue {
      Some(issue) => Err(issue)
      None => Ok(())
    }
  }
  if port.role == NativeResult &&
    port.result.rows > budget.guards.max_output_rows {
    return Err(Guard(port.role, budget.guards.max_output_rows, -1, OutputRows))
  }
  if port.role == NativeResult && receiving.output_stream is Some(stream) {
    return match stream.guard_issue {
      Some(issue) => Err(issue)
      None => Ok(())
    }
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
