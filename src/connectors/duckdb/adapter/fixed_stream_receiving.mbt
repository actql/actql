///|
/// Admitted content for an exact fixed Compute receiver; neither execution nor
/// independent storage evidence. The drained bytes still require Store sealing.
struct FixedComputeStreamReceipt {
  owner : FixedComputeReceiving
  admitted : @execution.AdmittedOutputStreamReceipt
}

///|
pub fn prepare_fixed_compute_stream_receiving(
  compute : FixedCompute,
  fields : Array[(String, PhysicalType)],
  physical : PhysicalResultLimits,
  retention : @execution.ValueLimits,
  max_metadata_work : Int,
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
  max_chunk_rows : Int,
  measurement? : @execution.FixedProducerMeasurement,
) -> Result[FixedComputeReceiving, FixedComputeReceivingIssue] {
  if max_chunk_rows <= 0 || max_batch_bytes <= 0 {
    return Err(Physical(InvalidLimits))
  }
  let value = match
    prepare_fixed_compute_receiving_impl(
      compute,
      fields,
      physical,
      retention,
      max_metadata_work,
      Some((wire, max_batch_bytes, max_chunk_rows)),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if measurement is Some(measurement) {
    match
      @execution.attach_fixed_producer_stream_measurement(
        measurement,
        value.stream.unwrap(),
      ) {
      Ok(_) => ()
      Err(issue) => {
        abort_fixed_compute_receiving(value)
        return Err(Guard(issue))
      }
    }
  }
  Ok(value)
}

///|
/// Admit at most one transport-bounded physical chunk. The next chunk is not
/// accepted until this one is drained, so backpressure bounds retained scratch.
pub fn receive_fixed_compute_stream_chunk(
  value : FixedComputeReceiving,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, FixedComputeReceivingIssue] {
  if !value.open ||
    value.stream is None ||
    value.pending is Some(_) ||
    value.pending_text is Some(_) {
    return Err(InvalidState)
  }
  if rows > value.stream_chunk_rows {
    abort_fixed_compute_receiving(value)
    return Err(Physical(RowLimit))
  }
  match receive_fixed_compute_physical_chunk(value, rows, columns) {
    Ok(batch) => {
      value.pending = if batch.rows == 0 { None } else { Some(batch) }
      value.pending_row = 0
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
/// Return one provisional canonical batch. The caller must await storage/credit
/// before pulling again; neither this receiver nor the encoder accumulates rows.
pub fn drain_fixed_compute_stream_row(
  value : FixedComputeReceiving,
) -> Result[String?, FixedComputeReceivingIssue] {
  guard value.open && value.stream is Some(stream) else {
    return Err(InvalidState)
  }
  if !fixed_compute_inputs_available(value.compute) {
    abort_fixed_compute_receiving(value)
    return Err(InputUnavailable)
  }
  if value.pending_text is Some(text) {
    value.pending_text = None
    return Ok(Some(text))
  }
  guard value.pending is Some(batch) else { return Ok(None) }
  let row = value.pending_row
  match
    @execution.append_admitted_output_stream(
      stream,
      @schema.field_count(value.physical.schema),
      column => physical_batch_cell(batch, row, column),
    ) {
    Ok(text) => {
      value.pending_row += 1
      if value.pending_row == batch.rows {
        value.pending = None
        value.pending_row = 0
      }
      Ok(Some(text))
    }
    Err(issue) => {
      abort_fixed_compute_receiving(value)
      Err(Stream(issue))
    }
  }
}

///|
/// Cross the Host boundary once for a bounded run of canonical rows. A row
/// that would exceed this frame remains provisional until the next drain; it
/// cannot permit another physical chunk or a successful finish meanwhile.
pub fn drain_fixed_compute_stream_batch(
  value : FixedComputeReceiving,
  max_bytes : Int,
  max_rows : Int,
) -> Result[String?, FixedComputeReceivingIssue] {
  if max_bytes <= 0 ||
    max_bytes > value.stream_batch_bytes ||
    max_rows <= 0 ||
    max_rows > 64 {
    return Err(Physical(InvalidLimits))
  }
  let output = StringBuilder()
  let mut bytes = 0
  let mut rows = 0
  while rows < max_rows {
    match drain_fixed_compute_stream_row(value) {
      Err(issue) => return Err(issue)
      Ok(None) => break
      Ok(Some(text)) => {
        let length = match @scalar.admit_utf8_length(text, max_bytes) {
          Ok(length) => length
          Err(_) => {
            if rows == 0 {
              return Ok(Some(text))
            }
            value.pending_text = Some(text)
            break
          }
        }
        if length > max_bytes - bytes {
          value.pending_text = Some(text)
          break
        }
        output.write_string(text)
        bytes += length
        rows += 1
      }
    }
  }
  if rows == 0 {
    Ok(None)
  } else {
    Ok(Some(output.to_string()))
  }
}

///|
pub fn finish_fixed_compute_stream_receiving(
  value : FixedComputeReceiving,
) -> Result[(FixedComputeStreamReceipt, String), FixedComputeReceivingIssue] {
  guard value.open &&
    value.stream is Some(stream) &&
    value.pending is None &&
    value.pending_text is None else {
    return Err(InvalidState)
  }
  if !fixed_compute_inputs_available(value.compute) {
    abort_fixed_compute_receiving(value)
    return Err(InputUnavailable)
  }
  if value.compute.query is CountGroup(query) &&
    @lower.count_group_key_count(query.group) == 0 &&
    value.physical.rows != 1 {
    abort_fixed_compute_receiving(value)
    return Err(InvalidShape)
  }
  match @execution.finish_admitted_output_stream(stream) {
    Ok((admitted, tail)) => {
      value.open = false
      value.finished = true
      value.stream = None
      cancel_physical_result(value.physical)
      Ok(({ owner: value, admitted, }, tail))
    }
    Err(issue) => {
      abort_fixed_compute_receiving(value)
      Err(Stream(issue))
    }
  }
}

///|
pub fn fixed_compute_stream_receipt_matches(
  receipt : FixedComputeStreamReceipt,
  receiving : FixedComputeReceiving,
) -> Bool {
  physical_equal(receipt.owner, receiving) &&
  receiving.finished &&
  fixed_compute_inputs_available(receiving.compute)
}

///|
pub fn fixed_compute_stream_receipt_content(
  receipt : FixedComputeStreamReceipt,
) -> @execution.AdmittedOutputStreamReceipt? {
  if fixed_compute_stream_receipt_matches(receipt, receipt.owner) {
    Some(receipt.admitted)
  } else {
    None
  }
}
