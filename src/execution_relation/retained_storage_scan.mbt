///|
/// Full-output representation transfer, not a receiving Compute port. Rows are
/// provisional until identity verification; this cannot discharge task guards.
struct RetainedStorageScan {
  storage : ProducerStorage
  expected : AdmittedOutputStreamReceipt
  stream : AdmittedOutputStream
  mut open : Bool
}

///|
struct VerifiedStorageScan {
  storage : ProducerStorage
  receipt : AdmittedOutputStreamReceipt
}

///|
pub fn prepare_retained_storage_scan(
  storage : ProducerStorage,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[RetainedStorageScan, CompletedImportIssue] {
  if !producer_storage_available(storage) {
    return Err(Unavailable)
  }
  guard storage.output.representation is Some(material) else {
    return Err(NotRetainedRepresentation)
  }
  let expected = material.receipt
  // Both are projections of this exact completed output, not a consumer's
  // possibly renamed/projected schema. No CID-based substitution is allowed.
  if !physical_equal(storage.schema, expected.schema) {
    return Err(IdentityMismatch)
  }
  if max_rows < expected.rows {
    return Err(Admission(CaptureLimit))
  }
  match
    prepare_admitted_stream(
      expected.owner,
      expected.target,
      max_rows,
      values,
      wire,
      max_batch_bytes,
      false,
    ) {
    Err(issue) => Err(Encoding(issue))
    Ok(stream) => Ok({ storage, expected, stream, open: true, })
  }
}

///|
pub fn cancel_retained_storage_scan(scan : RetainedStorageScan) -> Bool {
  if !scan.open {
    return false
  }
  scan.open = false
  cancel_admitted_output_stream(scan.stream) |> ignore
  true
}

///|
pub fn append_retained_storage_scan_wire(
  scan : RetainedStorageScan,
  text : String,
  limits : RetainedRowDecodeLimits,
) -> Result[Array[@admitted.CheckedValue], CompletedImportIssue] {
  if !scan.open {
    return Err(Closed)
  }
  if !producer_storage_available(scan.storage) {
    cancel_retained_storage_scan(scan) |> ignore
    return Err(Unavailable)
  }
  let values = match decode_retained_row(scan.expected.schema, text, limits) {
    Ok(values) => values
    Err(issue) => {
      cancel_retained_storage_scan(scan) |> ignore
      return Err(WireRow(issue))
    }
  }
  match
    append_admitted_output_stream(scan.stream, values.length(), column => {
      values.get(column)
    }) {
    Ok(_) => Ok(values)
    Err(issue) => {
      cancel_retained_storage_scan(scan) |> ignore
      Err(Encoding(issue))
    }
  }
}

///|
pub fn finish_retained_storage_scan(
  scan : RetainedStorageScan,
) -> Result[VerifiedStorageScan, CompletedImportIssue] {
  if !scan.open {
    return Err(Closed)
  }
  if !producer_storage_available(scan.storage) {
    cancel_retained_storage_scan(scan) |> ignore
    return Err(Unavailable)
  }
  scan.open = false
  let (receipt, _) = match finish_admitted_output_stream(scan.stream) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  let expected = scan.expected
  if receipt.cid != expected.cid ||
    receipt.rows != expected.rows ||
    receipt.bytes != expected.bytes ||
    receipt.nodes != expected.nodes ||
    receipt.depth != expected.depth ||
    receipt.usage != expected.usage ||
    !physical_equal(receipt.owner, expected.owner) ||
    receipt.target != expected.target ||
    !physical_equal(receipt.schema, expected.schema) {
    return Err(IdentityMismatch)
  }
  Ok({ storage: scan.storage, receipt, })
}

///|
pub fn verified_storage_scan_matches(
  scan : VerifiedStorageScan,
  storage : ProducerStorage,
) -> Bool {
  physical_equal(scan.storage, storage) &&
  scan.receipt.rows == producer_storage_row_count(storage) &&
  producer_storage_available(storage)
}
