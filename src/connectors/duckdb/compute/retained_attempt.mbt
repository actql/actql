///|
/// The installed Store supplies the exact admitted material before the common
/// task finisher runs. This stage is not success and does not attach a holding.
pub fn stage_retained_duckdb_compute_material(
  value : DuckDBComputeAttempt,
  material : @execution.RetainedOutputMaterial,
) -> Result[Unit, DuckDBComputeIssue] {
  guard value.live &&
    !value.completed &&
    value.streaming &&
    value.pending_material is None &&
    value.stream_receipt is Some(receipt) &&
    @duckdb.fixed_compute_stream_receipt_content(receipt) is Some(content) &&
    @execution.retained_output_matches_receipt(material, content) else {
    abort_duckdb_compute_attempt(value)
    return Err(Completion(NotRetained))
  }
  value.pending_material = Some(material)
  Ok(())
}

///|
pub fn begin_duckdb_compute_stream_result(
  value : DuckDBComputeAttempt,
  fields : Array[(String, @duckdb.PhysicalType)],
  wire : @execution.RowWireLimits,
  max_batch_bytes : Int,
  max_chunk_rows : Int,
) -> Result[Unit, DuckDBComputeIssue] {
  if value.managed {
    return Err(InvalidState)
  }
  if value.stream_transport is Some(bound) &&
    (
      max_batch_bytes <= 0 ||
      max_batch_bytes > bound.max_bytes ||
      max_chunk_rows <= 0 ||
      max_chunk_rows > bound.max_rows ||
      fields.length() > bound.max_columns
    ) {
    return Err(InvalidState)
  }
  if !duckdb_compute_inputs_ready(value) || value.receiving is Some(_) {
    return Err(InvalidState)
  }
  let capacity = @connector.fixed_compute_request_capacity(value.request)
  let physical = if capacity.max_rows < value.limits.physical.max_rows {
    { ..value.limits.physical, max_rows: capacity.max_rows, }
  } else {
    value.limits.physical
  }
  match
    @duckdb.prepare_fixed_compute_stream_receiving(
      value.compute,
      fields,
      physical,
      value.limits.retention,
      value.limits.metadata_work,
      wire,
      max_batch_bytes,
      max_chunk_rows,
      measurement=value.measurement,
    ) {
    Ok(receiving) => {
      value.streaming = true
      value.receiving = Some(receiving)
      Ok(())
    }
    Err(issue) => {
      abort_duckdb_compute_attempt(value)
      Err(Receiving(issue))
    }
  }
}

///|
pub fn receive_duckdb_compute_stream_chunk(
  value : DuckDBComputeAttempt,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, DuckDBComputeIssue] {
  guard value.live &&
    value.streaming &&
    value.stream_receipt is None &&
    value.receiving is Some(receiving) &&
    @duckdb.fixed_compute_join_validation_matches(
      value.compute,
      value.join_validation,
    ) else {
    return Err(InvalidState)
  }
  match @duckdb.receive_fixed_compute_stream_chunk(receiving, rows, columns) {
    Ok(_) => Ok(())
    Err(issue) => {
      abort_duckdb_compute_attempt(value)
      Err(Receiving(issue))
    }
  }
}

///|
pub fn drain_duckdb_compute_stream_row(
  value : DuckDBComputeAttempt,
) -> Result[String?, DuckDBComputeIssue] {
  guard value.live &&
    value.streaming &&
    value.stream_receipt is None &&
    value.receiving is Some(receiving) else {
    return Err(InvalidState)
  }
  match @duckdb.drain_fixed_compute_stream_row(receiving) {
    Ok(row) => Ok(row)
    Err(issue) => {
      abort_duckdb_compute_attempt(value)
      Err(Receiving(issue))
    }
  }
}

///|
pub fn drain_duckdb_compute_stream_batch(
  value : DuckDBComputeAttempt,
  max_bytes : Int,
  max_rows : Int,
) -> Result[String?, DuckDBComputeIssue] {
  guard value.live &&
    value.streaming &&
    value.stream_receipt is None &&
    value.receiving is Some(receiving) else {
    return Err(InvalidState)
  }
  match
    @duckdb.drain_fixed_compute_stream_batch(receiving, max_bytes, max_rows) {
    Ok(batch) => Ok(batch)
    Err(issue) => {
      abort_duckdb_compute_attempt(value)
      Err(Receiving(issue))
    }
  }
}

///|
pub fn finish_duckdb_compute_stream_result(
  value : DuckDBComputeAttempt,
) -> Result[
  (@execution.AdmittedOutputStreamReceipt, String),
  DuckDBComputeIssue,
] {
  guard value.live &&
    value.streaming &&
    value.stream_receipt is None &&
    value.receiving is Some(receiving) else {
    return Err(InvalidState)
  }
  match @duckdb.finish_fixed_compute_stream_receiving(receiving) {
    Ok((receipt, tail)) => {
      value.stream_receipt = Some(receipt)
      guard @duckdb.fixed_compute_stream_receipt_content(receipt)
        is Some(content) else {
        abort_duckdb_compute_attempt(value)
        return Err(InvalidState)
      }
      Ok((content, tail))
    }
    Err(issue) => {
      abort_duckdb_compute_attempt(value)
      Err(Receiving(issue))
    }
  }
}

///|
/// Physical encoded bytes for the exact, live staged result. This is not a
/// completion constructor; the common boundary still runs the full finisher.
pub fn retained_duckdb_compute_bytes(value : DuckDBComputeAttempt) -> Int64? {
  guard value.live &&
    !value.completed &&
    value.streaming &&
    (value.transport_matches)(value) &&
    value.receiving is Some(receiving) &&
    value.stream_receipt is Some(receipt) &&
    value.pending_material is Some(material) &&
    @duckdb.fixed_compute_stream_receipt_matches(receipt, receiving) &&
    @duckdb.fixed_compute_stream_receipt_content(receipt) is Some(content) &&
    @execution.retained_output_matches_receipt(material, content) else {
    return None
  }
  @execution.retained_output_storage_bytes(material)
}

///|
fn verified_compute_material(
  value : DuckDBComputeAttempt,
) -> @execution.RetainedOutputMaterial? {
  guard value.live &&
    !value.completed &&
    value.streaming &&
    (value.transport_matches)(value) &&
    value.receiving is Some(receiving) &&
    value.stream_receipt is Some(receipt) &&
    value.stream_measured is Some(measured) &&
    value.stream_demand is Some(demand) &&
    value.pending_material is Some(material) &&
    @duckdb.fixed_compute_stream_receipt_matches(receipt, receiving) &&
    @duckdb.fixed_compute_stream_receipt_content(receipt) is Some(content) else {
    return None
  }
  let capacity = @connector.fixed_compute_request_capacity(value.request)
  if !@duckdb.fixed_compute_stream_demand_matches(
      demand,
      value.compute,
      receipt,
      capacity.max_value_bytes,
    ) ||
    !@execution.fixed_producer_stream_measurement_matches(
      measured,
      @connector.fixed_compute_request_inputs(value.request),
      content,
      capacity.max_rows,
      capacity.max_value_bytes,
    ) ||
    !@execution.retained_output_matches_receipt(material, content) {
    return None
  }
  Some(material)
}

///|
fn complete_retained_duckdb_compute_attempt(
  value : DuckDBComputeAttempt,
  material : @execution.RetainedOutputMaterial,
) -> Result[@execution.CompletedOutput, DuckDBComputeIssue] {
  if !value.live || value.completed || !value.streaming {
    return Err(InvalidState)
  }
  let result = complete_retained_duckdb_compute_impl(value, material)
  value.pending_material = None
  if result is Err(_) {
    abort_duckdb_compute_attempt(value)
  }
  result
}

///|
fn complete_retained_duckdb_compute_impl(
  value : DuckDBComputeAttempt,
  material : @execution.RetainedOutputMaterial,
) -> Result[@execution.CompletedOutput, DuckDBComputeIssue] {
  guard value.stream_receipt is Some(receipt) else { return Err(InvalidState) }
  if !(value.transport_matches)(value) {
    return Err(UnverifiedTransport)
  }
  let capacity = @connector.fixed_compute_request_capacity(value.request)
  value.stream_demand = Some(
    match
      (if value.input_demand is Some(input_demand) {
        @duckdb.measure_fixed_compute_stream_demand(
          value.compute,
          receipt,
          capacity.max_value_bytes,
          value.limits.demand,
          input_demand~,
        )
      } else {
        @duckdb.measure_fixed_compute_stream_demand(
          value.compute,
          receipt,
          capacity.max_value_bytes,
          value.limits.demand,
        )
      }) {
      Ok(demand) => demand
      Err(issue) => return Err(Demand(issue))
    },
  )
  guard @duckdb.fixed_compute_stream_receipt_content(receipt) is Some(content) else {
    return Err(InvalidState)
  }
  value.stream_measured = Some(
    match
      @execution.finish_fixed_producer_stream_measurement(
        value.measurement,
        content,
      ) {
      Ok(measured) => measured
      Err(issue) => return Err(Guard(issue))
    },
  )
  value.pending_material = Some(material)
  match
    @execution.complete_trusted_retained_output(value.retained_port, value) {
    Ok(output) => {
      value.completed = true
      // Only this result's logical use restriction survives completion. The
      // stored material has its own copy lifetime, independent of its inputs.
      let live = value.retained_live
      Ok(@execution.restrict_completed_output(output, fn() { live.val }))
    }
    Err(issue) => Err(Completion(issue))
  }
}
