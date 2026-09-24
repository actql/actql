///|
/// Exact fixed-input result admission. No source locator, acquisition receipt,
/// transaction claim or success verifier is accepted at this data boundary.
struct FixedComputeReceiving {
  compute : FixedCompute
  physical : PhysicalResult
  mut retained : @execution.AdmittedOutput?
  mut stream : @execution.AdmittedOutputStream?
  mut pending : PhysicalBatch?
  mut pending_row : Int
  mut pending_text : String?
  stream_chunk_rows : Int
  stream_batch_bytes : Int
  mut open : Bool
  mut finished : Bool
}

///|
struct FixedComputeReceipt {
  owner : FixedComputeReceiving
  rows : @execution.AdmittedOutputRows
}

///|
pub(all) enum FixedComputeReceivingIssue {
  InputUnavailable
  InvalidState
  InvalidShape
  Physical(PhysicalResultIssue)
  Retention(@execution.CaptureIssue)
  Stream(@execution.OutputStreamIssue)
  Guard(@execution.FixedInputGuardIssue)
}

///|
pub fn prepare_fixed_compute_receiving(
  compute : FixedCompute,
  fields : Array[(String, PhysicalType)],
  physical : PhysicalResultLimits,
  retention : @execution.ValueLimits,
  max_metadata_work : Int,
) -> Result[FixedComputeReceiving, FixedComputeReceivingIssue] {
  prepare_fixed_compute_receiving_impl(
    compute,
    fields,
    physical,
    retention,
    max_metadata_work,
    None,
  )
}

///|
fn prepare_fixed_compute_receiving_impl(
  compute : FixedCompute,
  fields : Array[(String, PhysicalType)],
  physical : PhysicalResultLimits,
  retention : @execution.ValueLimits,
  max_metadata_work : Int,
  streaming : (@execution.RowWireLimits, Int, Int)?,
) -> Result[FixedComputeReceiving, FixedComputeReceivingIssue] {
  if !fixed_compute_inputs_available(compute) {
    return Err(InputUnavailable)
  }
  guard @lower.preparation_schema_at(
      @lower.bound_preparation(fixed_query_owner(compute.query)),
      fixed_query_target(compute.query),
    )
    is Some(schema) else {
    return Err(InvalidShape)
  }
  let physical = if compute.output_ceiling is Some(ceiling) &&
    ceiling < physical.max_rows {
    { ..physical, max_rows: ceiling, }
  } else {
    physical
  }
  let received_result = match fixed_query_output_names(compute.query) {
    Some(names) =>
      prepare_physical_result_named(
        schema, names, fields, physical, max_metadata_work,
      )
    None => prepare_physical_result(schema, fields, physical, max_metadata_work)
  }
  let received = match received_result {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let (retained, stream, chunk_rows, batch_bytes) = match streaming {
    Some((wire, batch_bytes, chunk_rows)) =>
      match
        @execution.prepare_admitted_output_stream(
          fixed_query_owner(compute.query),
          fixed_query_target(compute.query),
          physical.max_rows,
          retention,
          wire,
          batch_bytes,
          capture_value_measurement=true,
        ) {
        Ok(stream) => (None, Some(stream), chunk_rows, batch_bytes)
        Err(issue) => {
          cancel_physical_result(received)
          return Err(Stream(issue))
        }
      }
    None =>
      match
        @execution.prepare_admitted_output(
          fixed_query_owner(compute.query),
          fixed_query_target(compute.query),
          physical.max_rows,
          retention,
        ) {
        Ok(value) => (Some(value), None, 0, 0)
        Err(issue) => {
          cancel_physical_result(received)
          return Err(Retention(issue))
        }
      }
  }
  Ok({
    compute,
    physical: received,
    retained,
    stream,
    pending: None,
    pending_row: 0,
    pending_text: None,
    stream_chunk_rows: chunk_rows,
    stream_batch_bytes: batch_bytes,
    open: true,
    finished: false,
  })
}

///|
/// Transport failure/closure may revoke even a sealed provisional receipt.
/// This never revokes the immutable successful upstream producer.
pub fn abort_fixed_compute_receiving(value : FixedComputeReceiving) -> Unit {
  value.open = false
  value.finished = false
  cancel_physical_result(value.physical)
  if value.retained is Some(retained) {
    @execution.cancel_admitted_output(retained) |> ignore
  }
  value.retained = None
  if value.stream is Some(stream) {
    @execution.cancel_admitted_output_stream(stream) |> ignore
  }
  value.stream = None
  value.pending = None
  value.pending_row = 0
  value.pending_text = None
}

///|
pub fn receive_fixed_compute_chunk(
  value : FixedComputeReceiving,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, FixedComputeReceivingIssue] {
  if !value.open {
    return Err(InvalidState)
  }
  guard value.retained is Some(retained) else { return Err(InvalidState) }
  let batch = match receive_fixed_compute_physical_chunk(value, rows, columns) {
    Ok(batch) => batch
    Err(issue) => return Err(issue)
  }
  let width = @schema.field_count(value.physical.schema)
  for row in 0..<batch.rows {
    match
      @execution.append_admitted_output_cells(retained, width, column => {
        physical_batch_cell(batch, row, column)
      }) {
      Ok(_) => ()
      Err(issue) => {
        abort_fixed_compute_receiving(value)
        return Err(Retention(issue))
      }
    }
  }
  Ok(())
}

///|
fn receive_fixed_compute_physical_chunk(
  value : FixedComputeReceiving,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[PhysicalBatch, FixedComputeReceivingIssue] {
  if !fixed_compute_inputs_available(value.compute) {
    abort_fixed_compute_receiving(value)
    return Err(InputUnavailable)
  }
  // Shape-specific necessary bound, never a substitute for guards/provenance.
  let input_rows = @execution.producer_read_row_count(
    value.compute.imports[0].input,
  )
  let maximum = match value.compute.query {
    FilterSelect(_) => input_rows
    CountGroup(query) =>
      if @lower.count_group_key_count(query.group) == 0 {
        1
      } else {
        input_rows
      }
    // Output growth is not bounded by either input. Physical chunk admission
    // below enforces the selected/authored ceiling, before retaining results.
    InnerJoin(_) => value.physical.limits.max_rows
  }
  if !(value.compute.query is InnerJoin(_)) &&
    rows > maximum - value.physical.rows {
    abort_fixed_compute_receiving(value)
    return Err(InvalidShape)
  }
  let batch = match admit_physical_chunk(value.physical, rows, columns) {
    Ok(batch) => batch
    Err(issue) => {
      abort_fixed_compute_receiving(value)
      return Err(Physical(issue))
    }
  }
  Ok(batch)
}

///|
/// Seals data only. DB settlement, budgets and trusted execution proof are
/// separate requirements before this receipt can yield successful completion.
pub fn finish_fixed_compute_receiving(
  value : FixedComputeReceiving,
) -> Result[FixedComputeReceipt, FixedComputeReceivingIssue] {
  if !value.open {
    return Err(InvalidState)
  }
  guard value.retained is Some(retained) else { return Err(InvalidState) }
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
  let rows = match @execution.finish_admitted_output(retained) {
    Ok(rows) => rows
    Err(issue) => {
      abort_fixed_compute_receiving(value)
      return Err(Retention(issue))
    }
  }
  value.open = false
  value.retained = None
  value.finished = true
  cancel_physical_result(value.physical)
  Ok({ owner: value, rows, })
}

///|
pub fn fixed_compute_receipt_matches(
  receipt : FixedComputeReceipt,
  receiving : FixedComputeReceiving,
) -> Bool {
  physical_equal(receipt.owner, receiving) &&
  receiving.finished &&
  fixed_compute_inputs_available(receiving.compute)
}

///|
pub fn fixed_compute_receipt_rows(
  receipt : FixedComputeReceipt,
) -> @execution.AdmittedOutputRows? {
  if fixed_compute_receipt_matches(receipt, receipt.owner) {
    Some(receipt.rows)
  } else {
    None
  }
}
