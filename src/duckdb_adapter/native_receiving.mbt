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
  mut phase : ReceivingPhase
  mut validation : PhysicalResult?
  mut native : PhysicalResult?
  validation_batches : Array[PhysicalBatch]
  native_batches : Array[PhysicalBatch]
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
) -> Result[NativeReceiving, NativeReceivingIssue] {
  if limits.max_rows < 0 ||
    limits.max_cells < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    max_metadata_work < 0 {
    return Err(InvalidLimits)
  }
  Ok({
    scan,
    limits,
    metadata_work: max_metadata_work,
    phase: Metadata,
    validation: None,
    native: None,
    validation_batches: [],
    native_batches: [],
  })
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
  if row_count != 1 ||
    fields.length() != 1 ||
    columns.length() != 1 ||
    fields[0] != ("table_type", Varchar) ||
    @decode.array_length(columns[0]) != Some(1) {
    return Err(InvalidMetadata)
  }
  let cell = @decode.element_at(columns[0], 0).unwrap()
  guard @decode.text(cell) is Ok("BASE TABLE") else { return Err(NotBaseTable) }
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
      ValidationScan => value.validation_batches.push(batch)
      NativeResult => value.native_batches.push(batch)
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
