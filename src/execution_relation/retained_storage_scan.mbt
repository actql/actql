///|
/// Full-output representation transfer, not a receiving Compute port. Rows are
/// provisional until identity verification; this cannot discharge task guards.
struct RetainedStorageScan {
  storage : ProducerStorage
  expected : AdmittedOutputStreamReceipt
  stream : AdmittedOutputStream
  logical_writer : @encode.Writer?
  mut open : Bool
}

///|
struct VerifiedStorageScan {
  storage : ProducerStorage
  receipt : AdmittedOutputStreamReceipt
  logical : LogicalRelationIdentity?
}

///|
pub fn prepare_retained_storage_scan(
  storage : ProducerStorage,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[RetainedStorageScan, CompletedImportIssue] {
  prepare_storage_scan(storage, max_rows, values, wire, max_batch_bytes, None)
}

///|
/// Establish the Relation envelope identity during the same exact storage
/// verification. No rows are retained and no identity is issued for a partial,
/// changed or unavailable representation. Ordinary scans do not hash an envelope.
pub fn prepare_retained_relation_identity_scan(
  storage : ProducerStorage,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  logical_wire : RowWireLimits,
  max_batch_bytes : Int,
) -> Result[RetainedStorageScan, CompletedImportIssue] {
  prepare_storage_scan(
    storage,
    max_rows,
    values,
    wire,
    max_batch_bytes,
    Some(logical_wire),
  )
}

///|
fn prepare_storage_scan(
  storage : ProducerStorage,
  max_rows : Int,
  values : ValueLimits,
  wire : RowWireLimits,
  max_batch_bytes : Int,
  logical_wire : RowWireLimits?,
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
  if logical_wire is Some(limits) {
    if !row_wire_valid_limits(limits) {
      return Err(Encoding(Wire(InvalidLimits)))
    }
    if limits.max_columns < wire.max_columns ||
      limits.max_order_work < wire.max_order_work {
      return Err(Encoding(Wire(OrderLimit)))
    }
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
    Ok(stream) =>
      try {
        let logical_writer = logical_wire.map(limits => {
          let writer = @encode.hashing_writer(
            limits.max_bytes,
            limits.max_nodes,
            limits.max_depth,
          )
          @encode.begin_object(writer)
          @encode.key(writer, "sort")
          @encode.string_value(writer, "relation")
          @encode.key(writer, "value")
          @encode.begin_array(writer)
          writer
        })
        Ok({ storage, expected, stream, logical_writer, open: true, })
      } catch {
        issue => {
          cancel_admitted_output_stream(stream) |> ignore
          Err(Encoding(Wire(Encoding(issue))))
        }
      }
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
  append_retained_storage_scan_values(scan, values)
}

///|
/// Typed, bounded representation conversion through the same exact content
/// verifier. This does not assert import success or consumer readiness.
pub fn append_retained_storage_scan_values(
  scan : RetainedStorageScan,
  values : Array[@admitted.CheckedValue],
) -> Result[Array[@admitted.CheckedValue], CompletedImportIssue] {
  if !scan.open {
    return Err(Closed)
  }
  if !producer_storage_available(scan.storage) {
    cancel_retained_storage_scan(scan) |> ignore
    return Err(Unavailable)
  }
  match
    append_admitted_output_stream(scan.stream, values.length(), column => {
      values.get(column)
    }) {
    Ok(_) =>
      try {
        if scan.logical_writer is Some(writer) {
          @encode.begin_object(writer)
          for (name, column) in scan.stream.order.columns {
            @encode.key(writer, name)
            @admitted.emit_checked_wire_value(values[column], writer)
          }
          @encode.end_object(writer)
        }
        Ok(values)
      } catch {
        issue => {
          cancel_retained_storage_scan(scan) |> ignore
          Err(Encoding(Wire(Encoding(issue))))
        }
      }
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
  try {
    let logical = scan.logical_writer.map(writer => {
      @encode.end_array(writer)
      @encode.end_object(writer)
      let (hash, bytes, nodes, _) = @encode.finish_hash_metrics(writer)
      { cid: "sha256:" + hash, bytes, nodes, rows: receipt.rows, }
    })
    Ok({ storage: scan.storage, receipt, logical, })
  } catch {
    issue => Err(Encoding(Wire(Encoding(issue))))
  }
}

///|
/// Only a successful full scan can expose the requested identity, while the
/// exact retained output remains available. A bare payload CID is not enough.
pub fn verified_storage_scan_relation_identity(
  scan : VerifiedStorageScan,
) -> LogicalRelationIdentity? {
  if !producer_storage_available(scan.storage) {
    return None
  }
  scan.logical
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

///|
/// For an installed Store that sealed the canonical output bytes against the
/// receipt CID and verified those same bytes during this read. This comparison
/// is not itself a Store read or authority to trust an arbitrary claimed CID.
/// The physical adapter must also prove that its provisional import finished.
pub fn retained_storage_canonical_copy_matches(
  storage : ProducerStorage,
  cid : String,
  bytes : Int,
  rows : Int,
) -> Bool {
  guard producer_storage_available(storage) &&
    storage.output.representation is Some(material) else {
    return false
  }
  let receipt = material.receipt
  physical_equal(storage.schema, receipt.schema) &&
  receipt.cid == cid &&
  receipt.bytes == bytes &&
  receipt.rows == rows
}
