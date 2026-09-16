///|
/// Bounded provisional output, not capture or completion authority. The Store
/// must consume all returned bytes and bind its holding to the exact receipt.
priv struct NativeOutputStream {
  admitted : @execution.AdmittedOutputStream
  wire : @execution.RowWireLimits
  max_chunk_rows : Int
  mut pending : PhysicalBatch?
  mut offset : Int
  mut rows : Int
  mut guard_issue : NativeReceivingIssue?
  mut issue : @execution.OutputStreamIssue?
  mut receipt : @execution.AdmittedOutputStreamReceipt?
  mut tail : String?
}

///|
pub fn stream_native_output(
  value : NativeReceiving,
  max_rows : Int,
  retention : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
  max_chunk_rows : Int,
) -> Result[Unit, NativeReceivingIssue] {
  if !(value.phase is Metadata) || value.output_stream is Some(_) {
    return Err(InvalidState)
  }
  if max_chunk_rows < 0 {
    return Err(InvalidLimits)
  }
  match
    @execution.prepare_admitted_output_stream(
      value.scan.query.owner,
      @pipeline.Step(1),
      max_rows,
      retention,
      wire,
      max_batch_bytes,
    ) {
    Err(issue) => Err(Stream(issue))
    Ok(admitted) => {
      value.output_stream = Some({
        admitted,
        wire,
        max_chunk_rows,
        pending: None,
        offset: 0,
        rows: 0,
        guard_issue: None,
        issue: None,
        receipt: None,
        tail: None,
      })
      Ok(())
    }
  }
}

///|
/// Drain before accepting another native chunk. Measured guards are reported
/// after the receipt's physical admission completes; partial text is provisional.
pub fn drain_native_output_row(
  value : NativeReceiving,
) -> Result[String?, NativeReceivingIssue] {
  guard value.phase is Reading(NativeResult, _) &&
    value.output_stream is Some(stream) else {
    return Err(InvalidState)
  }
  guard stream.pending is Some(batch) else { return Ok(None) }
  let row = stream.offset
  if stream.guard_issue is None {
    if value.measurement.work == 0 {
      stream.guard_issue = Some(
        Guard(NativeResult, stream.rows, -1, MeasurementWork),
      )
    } else {
      value.measurement.work -= 1
      match measure_native_record(value.measurement, batch, row) {
        Ok(_) => ()
        Err(issue) =>
          stream.guard_issue = Some(Guard(NativeResult, stream.rows, -1, issue))
      }
    }
  }
  let mut text = ""
  if stream.issue is None {
    match
      @execution.append_admitted_output_stream(
        stream.admitted,
        batch.owner.mappings.length(),
        column => physical_batch_cell(batch, row, column),
      ) {
      Ok(chunk) => text = chunk
      Err(issue) => stream.issue = Some(issue)
    }
  }
  stream.rows += 1
  stream.offset += 1
  if stream.offset == batch.rows {
    stream.pending = None
  }
  // Empty provisional text after a deferred error is not end-of-receipt.
  Ok(Some(text))
}

///|
pub fn finish_native_output_stream(
  value : NativeReceiving,
) -> Result[
  (@execution.AdmittedOutputStreamReceipt, String)?,
  NativeReceivingIssue,
] {
  guard value.phase is Received && value.output_stream is Some(stream) else {
    return Err(InvalidState)
  }
  // No successful material is exposed after encoding/retention failure. Its
  // saved issue is consumed after demand checks by normal receipt verification.
  if stream.issue is Some(_) {
    return Ok(None)
  }
  guard stream.receipt is Some(receipt) && stream.tail is Some(tail) else {
    return Err(InvalidState)
  }
  stream.tail = None
  Ok(Some((receipt, tail)))
}

///|
pub fn native_output_stream_matches(
  value : NativeReceiving,
  receipt : @execution.AdmittedOutputStreamReceipt,
) -> Bool {
  value.phase is Received &&
  value.output_stream is Some(stream) &&
  stream.receipt is Some(actual) &&
  physical_equal(actual, receipt)
}

///|
pub fn native_output_stream_material_matches(
  value : NativeReceiving,
  material : @execution.RetainedOutputMaterial,
) -> Bool {
  value.phase is Received &&
  value.output_stream is Some(stream) &&
  stream.receipt is Some(receipt) &&
  @execution.retained_output_matches_receipt(material, receipt)
}

///|
pub fn native_output_retained_rows(value : NativeReceiving) -> Int {
  let mut rows = 0
  for batch in value.native_batches {
    rows += batch.rows
  }
  if value.output_stream is Some(stream) && stream.pending is Some(batch) {
    rows += batch.rows
  }
  rows
}

///|
fn native_stream_digest(
  value : NativeReceiving,
  limits : @execution.RowWireLimits,
) -> Result[ReceiptDigest, @execution.RowWireIssue] {
  guard value.output_stream is Some(stream) && stream.receipt is Some(receipt) else {
    return Err(OrderLimit)
  }
  let (cid, bytes, nodes, rows) = @execution.output_stream_identity(receipt)
  if bytes > limits.max_bytes ||
    nodes > limits.max_nodes ||
    limits.max_depth != stream.wire.max_depth {
    return Err(Encoding(@encode.OutputLimit))
  }
  let width = @schema.field_count(value.scan.output_schema)
  if width > limits.max_columns || width > limits.max_order_work {
    return Err(OrderLimit)
  }
  let names = Array::makei(width, column => {
    @schema.reference_name(
      @schema.field_at(value.scan.output_schema, column).unwrap().name,
    )
  })
  @execution.prepare_row_wire_order(
    names,
    limits.max_columns,
    limits.max_order_work - width,
  ).map(order => {
    order,
    columns: width,
    cid,
    bytes,
    nodes,
    rows,
    work: width + @execution.row_wire_order_work(order),
  })
}
