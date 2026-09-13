///|
/// Exact fixed-input result admission. No source locator, acquisition receipt,
/// transaction claim or success verifier is accepted at this data boundary.
struct FixedComputeReceiving {
  compute : FixedCompute
  physical : PhysicalResult
  mut retained : @execution.AdmittedOutput?
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
}

///|
pub fn prepare_fixed_compute_receiving(
  compute : FixedCompute,
  fields : Array[(String, PhysicalType)],
  physical : PhysicalResultLimits,
  retention : @execution.ValueLimits,
  max_metadata_work : Int,
) -> Result[FixedComputeReceiving, FixedComputeReceivingIssue] {
  let input = compute.imported.input
  if !@execution.producer_read_available(input) {
    return Err(InputUnavailable)
  }
  guard @pipeline.schema_at(
      @lower.pipeline(@lower.bound_preparation(compute.query.owner)),
      @pipeline.Step(1),
    )
    is Some(schema) else {
    return Err(InvalidShape)
  }
  let received = match
    prepare_physical_result(schema, fields, physical, max_metadata_work) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let retained = match
    @execution.prepare_admitted_output(
      compute.query.owner,
      @pipeline.Step(1),
      physical.max_rows,
      retention,
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_physical_result(received)
      return Err(Retention(issue))
    }
  }
  Ok({
    compute,
    physical: received,
    retained: Some(retained),
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
  if !@execution.producer_read_available(value.compute.imported.input) {
    abort_fixed_compute_receiving(value)
    return Err(InputUnavailable)
  }
  // The selected filter/select cannot invent input occurrences. This check is
  // necessary, not a substitute for exact SQL/transport/semantic verification.
  if rows >
    @execution.producer_read_row_count(value.compute.imported.input) -
    value.physical.rows {
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
/// Seals data only. DB settlement, budgets and trusted execution proof are
/// separate requirements before this receipt can yield successful completion.
pub fn finish_fixed_compute_receiving(
  value : FixedComputeReceiving,
) -> Result[FixedComputeReceipt, FixedComputeReceivingIssue] {
  if !value.open {
    return Err(InvalidState)
  }
  guard value.retained is Some(retained) else { return Err(InvalidState) }
  if !@execution.producer_read_available(value.compute.imported.input) {
    abort_fixed_compute_receiving(value)
    return Err(InputUnavailable)
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
  @execution.producer_read_available(receiving.compute.imported.input)
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
