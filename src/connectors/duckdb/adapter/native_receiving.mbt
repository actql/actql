///|
pub(all) enum NativeReceiptRole {
  ValidationScan
  NativeResult
} derive(Eq)

///|
pub(all) enum NativeReceivingIssue {
  InvalidLimits
  InvalidState
  ForeignReceipt
  NotBaseTable
  InvalidMetadata
  Values(PhysicalResultIssue)
  Guard(NativeReceiptRole, Int, Int, NativeValueIssue)
  Stream(@execution.OutputStreamIssue)
}

///|
priv enum ReceivingPhase {
  Metadata
  ReadyValidation
  Reading(NativeReceiptRole, PhysicalResult)
  ReadyNative
  Received
  Failed
}

///|
/// Provisional, Host-owned receiving state. Finishing both receipts is not
/// execution evidence: native semantics, guards, retention and read-view binding
/// must still succeed before a separate issuer may construct capture evidence.
struct NativeReceiving {
  scan : NativeScan
  limits : PhysicalResultLimits
  metadata_work : Int
  initial_measurement : @execution.FixedInputGuardMeasureLimits
  measurement : NativeValueBudget
  mut phase : ReceivingPhase
  mut validation : PhysicalResult?
  mut native : PhysicalResult?
  validation_batches : Array[PhysicalBatch]
  native_batches : Array[PhysicalBatch]
  mut validation_stream : NativeValidationStream?
  mut output_stream : NativeOutputStream?
}

///|
struct NativeReceiptPort {
  owner : NativeReceiving
  role : NativeReceiptRole
  result : PhysicalResult
}

///|
pub fn prepare_native_receiving(
  scan : NativeScan,
  limits : PhysicalResultLimits,
  max_metadata_work : Int,
  guards : NativeValueGuards,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[NativeReceiving, NativeReceivingIssue] {
  if limits.max_rows < 0 ||
    limits.max_cells < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    max_metadata_work < 0 ||
    guards.max_value_bytes < 0 ||
    guards.max_output_rows < 0 ||
    measurement.max_work < 0 ||
    measurement.max_bytes < 0 ||
    measurement.max_nodes < 0 ||
    measurement.max_depth < 0 {
    return Err(InvalidLimits)
  }
  Ok({
    scan,
    limits,
    metadata_work: max_metadata_work,
    initial_measurement: measurement,
    measurement: {
      guards,
      work: measurement.max_work,
      bytes: measurement.max_bytes,
      nodes: measurement.max_nodes,
      depth: measurement.max_depth,
    },
    phase: Metadata,
    validation: None,
    native: None,
    validation_batches: [],
    native_batches: [],
    validation_stream: None,
    output_stream: None,
  })
}

///|
/// Logical top-level value measurement charged while admitting both receipts.
/// This is neither predicate demand nor observed physical CPU work.
pub fn native_receiving_measurement_usage(
  value : NativeReceiving,
) -> (Int, Int, Int) {
  (
    value.initial_measurement.max_work - value.measurement.work,
    value.initial_measurement.max_bytes - value.measurement.bytes,
    value.initial_measurement.max_nodes - value.measurement.nodes,
  )
}

///|
pub fn abort_native_receiving(value : NativeReceiving) -> Unit {
  value.phase = Failed
  if value.validation is Some(result) {
    cancel_physical_result(result)
  }
  if value.native is Some(result) {
    cancel_physical_result(result)
  }
  value.validation_batches.clear()
  value.native_batches.clear()
  value.validation_stream = None
  if value.output_stream is Some(stream) {
    @execution.cancel_admitted_output_stream(stream.admitted) |> ignore
    stream.pending = None
  }
  value.output_stream = None
}

///|
pub fn admit_native_table_metadata(
  value : NativeReceiving,
  row_count : Int,
  fields : Array[(String, PhysicalType)],
  columns : Array[@decode.Cursor],
) -> Result[Unit, NativeReceivingIssue] {
  if !(value.phase is Metadata) {
    abort_native_receiving(value)
    return Err(InvalidState)
  }
  value.phase = Failed
  match validate_source_table_metadata(row_count, fields, columns) {
    Ok(_) => ()
    Err(InvalidMetadata) => return Err(InvalidMetadata)
    Err(NotBaseTable) => return Err(NotBaseTable)
  }
  value.phase = ReadyValidation
  Ok(())
}

///|
pub fn begin_native_receipt(
  value : NativeReceiving,
  role : NativeReceiptRole,
  fields : Array[(String, PhysicalType)],
) -> Result[NativeReceiptPort, NativeReceivingIssue] {
  let ready = match (value.phase, role) {
    (Failed, _) => return Err(InvalidState)
    (ReadyValidation, ValidationScan) | (ReadyNative, NativeResult) => true
    _ => false
  }
  if !ready {
    abort_native_receiving(value)
    return Err(InvalidState)
  }
  let limits = match value.validation {
    None => value.limits
    Some(prior) => {
      let (rows, cells, nodes, bytes) = physical_result_usage(prior)
      {
        max_rows: value.limits.max_rows - rows,
        max_cells: value.limits.max_cells - cells,
        max_nodes: value.limits.max_nodes - nodes,
        max_text_bytes: value.limits.max_text_bytes - bytes,
      }
    }
  }
  let result = match
    (match role {
      ValidationScan =>
        prepare_scan_validation_receiver(
          value.scan,
          fields,
          limits,
          value.metadata_work,
        )
      NativeResult =>
        prepare_scan_output_receiver(
          value.scan,
          fields,
          limits,
          value.metadata_work,
        )
    }) {
    Ok(result) => result
    Err(issue) => {
      abort_native_receiving(value)
      return Err(Values(issue))
    }
  }
  match role {
    ValidationScan => value.validation = Some(result)
    NativeResult => value.native = Some(result)
  }
  value.phase = Reading(role, result)
  if role == ValidationScan && value.validation_stream is Some(stream) {
    start_validation_digest(stream, result)
  }
  Ok({ owner: value, role, result, })
}

///|
fn check_receipt_port(
  value : NativeReceiving,
  port : NativeReceiptPort,
) -> Result[Unit, NativeReceivingIssue] {
  if !physical_equal(value, port.owner) {
    abort_native_receiving(value)
    return Err(ForeignReceipt)
  }
  guard value.phase is Reading(role, result) &&
    role == port.role &&
    physical_equal(result, port.result) else {
    abort_native_receiving(value)
    return Err(InvalidState)
  }
  Ok(())
}

///|
pub fn accept_native_receipt_chunk(
  value : NativeReceiving,
  port : NativeReceiptPort,
  row_count : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, NativeReceivingIssue] {
  match check_receipt_port(value, port) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if port.role == ValidationScan &&
    value.validation_stream is Some(stream) &&
    row_count > stream.max_chunk_rows {
    abort_native_receiving(value)
    return Err(Values(RowLimit))
  }
  if port.role == NativeResult && value.output_stream is Some(stream) {
    if stream.pending is Some(_) || row_count > stream.max_chunk_rows {
      abort_native_receiving(value)
      return Err(InvalidState)
    }
  }
  let batch = match admit_physical_chunk(port.result, row_count, columns) {
    Ok(batch) => batch
    Err(issue) => {
      abort_native_receiving(value)
      return Err(Values(issue))
    }
  }
  // Positive batches are bounded by the cumulative row ceiling. Empty chunks
  // do not create unbounded retained container roots.
  if row_count > 0 {
    match port.role {
      ValidationScan =>
        match value.validation_stream {
          Some(stream) => consume_validation_batch(value, stream, batch)
          None => value.validation_batches.push(batch)
        }
      NativeResult =>
        match value.output_stream {
          Some(stream) => {
            stream.pending = Some(batch)
            stream.offset = 0
          }
          None => value.native_batches.push(batch)
        }
    }
  }
  Ok(())
}

///|
pub fn finish_native_receipt(
  value : NativeReceiving,
  port : NativeReceiptPort,
) -> Result[Unit, NativeReceivingIssue] {
  match check_receipt_port(value, port) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if port.role == NativeResult &&
    value.output_stream is Some(stream) &&
    stream.pending is Some(_) {
    abort_native_receiving(value)
    return Err(InvalidState)
  }
  match measure_native_receipt(value, port) {
    Ok(_) => ()
    Err(issue) => {
      abort_native_receiving(value)
      return Err(issue)
    }
  }
  if port.role == ValidationScan && value.validation_stream is Some(stream) {
    finish_validation_digest(stream, port.result)
  }
  if port.role == NativeResult && value.output_stream is Some(stream) {
    if stream.issue is None {
      match @execution.finish_admitted_output_stream(stream.admitted) {
        Ok((receipt, tail)) => {
          stream.receipt = Some(receipt)
          stream.tail = Some(tail)
        }
        Err(issue) => stream.issue = Some(issue)
      }
    }
  }
  cancel_physical_result(port.result)
  value.phase = match port.role {
    ValidationScan => ReadyNative
    NativeResult => Received
  }
  Ok(())
}

///|
pub fn native_receiving_scan(value : NativeReceiving) -> NativeScan {
  value.scan
}

///|
pub fn native_receiving_has_both(value : NativeReceiving) -> Bool {
  value.phase is Received
}
