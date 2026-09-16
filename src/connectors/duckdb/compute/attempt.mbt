///|
pub(all) struct DuckDBComputeLimits {
  values : @execution.FixedInputGuardMeasureLimits
  demand : @execution.FixedInputGuardMeasureLimits
  physical : @duckdb.PhysicalResultLimits
  retention : @execution.ValueLimits
  metadata_work : Int
  completion_entries : Int
  completion_name_bytes : Int
}

///|
pub(all) enum DuckDBComputeIssue {
  NotSelected
  ForeignPreparation
  InvalidState
  UnverifiedTransport
  Guard(@execution.FixedInputGuardIssue)
  JoinValidation(@execution.RowIssue)
  Receiving(@duckdb.FixedComputeReceivingIssue)
  Demand(@duckdb.NativeDemandIssue)
  Completion(@execution.TrustedOutputIssue)
  InputStream(@duckdb.FixedImportStreamIssue)
  ManagedValues(@duckdb.ManagedPhysicalOutputIssue)
}

///|
/// Connector-owned attempt. The verifier is trusted runtime wiring, never a
/// callback provided by a Program or ordinary capability registration.
struct DuckDBComputeAttempt {
  generated : @execution.CompletionPreparation
  request : @connector.FixedComputeRequest
  compute : @duckdb.FixedCompute
  port : @execution.TrustedOutputPort[DuckDBComputeAttempt]
  retained_port : @execution.TrustedRetainedOutputPort[DuckDBComputeAttempt]
  limits : DuckDBComputeLimits
  measurement : @execution.FixedProducerMeasurement
  input_streams : Array[@duckdb.FixedImportStream?]
  mut input_demand : @duckdb.FixedImportDemand?
  mut join_validation : @execution.FixedJoinValidation?
  join_stream : @execution.FixedJoinStream?
  transport_matches : (DuckDBComputeAttempt) -> Bool
  mut receiving : @duckdb.FixedComputeReceiving?
  mut receipt : @duckdb.FixedComputeReceipt?
  mut measured : @execution.FixedProducerMeasuredOutput?
  mut demand : @duckdb.FixedComputeDemand?
  mut completed : Bool
  // Sealed only after the trusted completion port accepts the exact rows.
  // Retention belongs to this Compute, not to its input's future availability.
  mut completed_rows : @execution.AdmittedOutputRows?
  mut streaming : Bool
  retained_required : Bool
  stream_transport : @duckdb.TransportColumnLimits?
  mut stream_receipt : @duckdb.FixedComputeStreamReceipt?
  mut stream_measured : @execution.FixedProducerStreamMeasuredOutput?
  mut stream_demand : @duckdb.FixedComputeStreamDemand?
  mut pending_material : @execution.RetainedOutputMaterial?
  retained_live : Ref[Bool]
  mut live : Bool
  mut managed : Bool
}

///|
pub fn start_duckdb_compute_attempt(
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@duckdb.FixedCompute],
  generated : @execution.CompletionPreparation,
  limits : DuckDBComputeLimits,
  transport_matches : (DuckDBComputeAttempt) -> Bool,
  retained_required? : Bool = false,
  stream_transport? : @duckdb.TransportColumnLimits,
) -> Result[DuckDBComputeAttempt, DuckDBComputeIssue] {
  if stream_transport is Some(bound) &&
    (
      !retained_required ||
      bound.max_bytes <= 0 ||
      bound.max_nodes <= 0 ||
      bound.max_rows <= 0 ||
      bound.max_columns <= 0 ||
      bound.max_text_bytes < 0
    ) {
    return Err(InvalidState)
  }
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(compute) else {
    return Err(NotSelected)
  }
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  if !@duckdb.fixed_compute_inputs_match(
      compute,
      @connector.fixed_compute_request_inputs(request),
    ) {
    return Err(ForeignPreparation)
  }
  if !physical_equal(
      @execution.completion_preparation_owner(generated),
      @connector.fixed_compute_request_owner(request),
    ) ||
    @connector.fixed_compute_request_capacity(request).common_fragment
    is Some(_) {
    return Err(ForeignPreparation)
  }
  let measurement = match
    @execution.prepare_streamed_fixed_producer_measurement(
      @connector.fixed_compute_request_inputs(request),
      @duckdb.fixed_query_target(@duckdb.fixed_compute_query(compute)),
      max_rows=@connector.fixed_compute_request_capacity(request).max_rows,
      max_value_bytes=@connector.fixed_compute_request_capacity(request).max_value_bytes,
      limits.values,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Guard(issue))
  }
  let join_stream = match @duckdb.prepare_fixed_compute_join_stream(compute) {
    Ok(value) => value
    Err(issue) => return Err(JoinValidation(issue))
  }
  let join_validation = if join_stream is Some(_) {
    None
  } else {
    match @duckdb.validate_fixed_compute_join(compute) {
      Ok(value) => value
      Err(issue) => return Err(JoinValidation(issue))
    }
  }
  let port = match
    @execution.prepare_trusted_output_port(
      generated,
      @duckdb.fixed_query_target(@duckdb.fixed_compute_query(compute)),
      limits.completion_entries,
      limits.completion_name_bytes,
      verified_compute_rows,
      inputs=@connector.fixed_compute_request_inputs(request),
    ) {
    Ok(port) => port
    Err(issue) => return Err(Completion(issue))
  }
  let retained_port = match
    @execution.prepare_trusted_retained_output_port(
      generated,
      @duckdb.fixed_query_target(@duckdb.fixed_compute_query(compute)),
      limits.completion_entries,
      limits.completion_name_bytes,
      verified_compute_material,
      inputs=@connector.fixed_compute_request_inputs(request),
    ) {
    Ok(port) => port
    Err(issue) => return Err(Completion(issue))
  }
  Ok({
    generated,
    request,
    compute,
    port,
    retained_port,
    limits,
    measurement,
    input_streams: Array::make(
      @duckdb.fixed_compute_import_count(compute),
      None,
    ),
    input_demand: None,
    join_validation,
    join_stream,
    transport_matches,
    receiving: None,
    receipt: None,
    measured: None,
    demand: None,
    completed: false,
    completed_rows: None,
    streaming: false,
    retained_required,
    stream_transport,
    stream_receipt: None,
    stream_measured: None,
    stream_demand: None,
    pending_material: None,
    retained_live: Ref(true),
    live: true,
    managed: false,
  })
}

///|
pub fn duckdb_compute_attempt_plan(
  value : DuckDBComputeAttempt,
) -> @duckdb.FixedCompute {
  value.compute
}

///|
pub fn begin_duckdb_compute_result(
  value : DuckDBComputeAttempt,
  fields : Array[(String, @duckdb.PhysicalType)],
) -> Result[Unit, DuckDBComputeIssue] {
  if value.managed ||
    value.retained_required ||
    !duckdb_compute_inputs_ready(value) ||
    value.receiving is Some(_) {
    return Err(InvalidState)
  }
  match
    @duckdb.prepare_fixed_compute_receiving(
      value.compute,
      fields,
      if @connector.fixed_compute_request_capacity(value.request).max_rows <
        value.limits.physical.max_rows {
        {
          ..value.limits.physical,
          max_rows: @connector.fixed_compute_request_capacity(value.request).max_rows,
        }
      } else {
        value.limits.physical
      },
      value.limits.retention,
      value.limits.metadata_work,
    ) {
    Ok(receiving) => {
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
pub fn receive_duckdb_compute_chunk(
  value : DuckDBComputeAttempt,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, DuckDBComputeIssue] {
  guard value.live &&
    !value.streaming &&
    @duckdb.fixed_compute_join_validation_matches(
      value.compute,
      value.join_validation,
    ) &&
    value.receipt is None &&
    value.receiving is Some(receiving) else {
    return Err(InvalidState)
  }
  match @duckdb.receive_fixed_compute_chunk(receiving, rows, columns) {
    Ok(_) => Ok(())
    Err(issue) => {
      abort_duckdb_compute_attempt(value)
      Err(Receiving(issue))
    }
  }
}

///|
pub fn finish_duckdb_compute_result(
  value : DuckDBComputeAttempt,
) -> Result[Unit, DuckDBComputeIssue] {
  guard value.live &&
    !value.streaming &&
    value.receipt is None &&
    value.receiving is Some(receiving) else {
    return Err(InvalidState)
  }
  match @duckdb.finish_fixed_compute_receiving(receiving) {
    Ok(receipt) => {
      value.receipt = Some(receipt)
      Ok(())
    }
    Err(issue) => {
      abort_duckdb_compute_attempt(value)
      Err(Receiving(issue))
    }
  }
}

///|
fn verified_compute_rows(
  value : DuckDBComputeAttempt,
) -> @execution.AdmittedOutputRows? {
  if value.completed {
    // Keep this attempt's own transport/retention revocation live. Receipt,
    // demand and input measurement were sealed at successful completion;
    // rechecking them here would incorrectly re-admit a now-closed upstream.
    return if value.live && (value.transport_matches)(value) {
      value.completed_rows
    } else {
      None
    }
  }
  guard value.live &&
    (value.transport_matches)(value) &&
    value.receiving is Some(receiving) &&
    value.receipt is Some(receipt) &&
    value.measured is Some(measured) &&
    value.demand is Some(demand) &&
    @duckdb.fixed_compute_receipt_matches(receipt, receiving) &&
    @duckdb.fixed_compute_demand_matches(
      demand,
      value.compute,
      receipt,
      @connector.fixed_compute_request_capacity(value.request).max_value_bytes,
    ) &&
    @duckdb.fixed_compute_receipt_rows(receipt) is Some(rows) &&
    @execution.fixed_producer_measurement_matches(
      measured,
      @connector.fixed_compute_request_inputs(value.request),
      rows,
      @connector.fixed_compute_request_capacity(value.request).max_rows,
      @connector.fixed_compute_request_capacity(value.request).max_value_bytes,
    ) else {
    return None
  }
  Some(rows)
}

///|
/// Settlement is necessary, not sufficient. This installs the fixed verifier;
/// raw rows/CIDs and successful SQL cannot bypass capacity and ownership checks.
pub fn complete_duckdb_compute_attempt(
  value : DuckDBComputeAttempt,
) -> Result[@execution.CompletedOutput, DuckDBComputeIssue] {
  if !value.live || value.completed || value.managed {
    return Err(InvalidState)
  }
  if value.streaming {
    guard value.pending_material is Some(material) else {
      abort_duckdb_compute_attempt(value)
      return Err(Completion(NotRetained))
    }
    return complete_retained_duckdb_compute_attempt(value, material)
  }
  let result = complete_duckdb_compute_impl(value)
  if result is Err(_) {
    abort_duckdb_compute_attempt(value)
  }
  result
}

///|
fn complete_duckdb_compute_impl(
  value : DuckDBComputeAttempt,
) -> Result[@execution.CompletedOutput, DuckDBComputeIssue] {
  guard value.receipt is Some(receipt) else { return Err(InvalidState) }
  if !(value.transport_matches)(value) {
    return Err(UnverifiedTransport)
  }
  let capacity = @connector.fixed_compute_request_capacity(value.request)
  value.demand = Some(
    match
      (if value.input_demand is Some(input_demand) {
        @duckdb.measure_fixed_compute_demand(
          value.compute,
          receipt,
          capacity.max_value_bytes,
          value.limits.demand,
          input_demand~,
        )
      } else {
        @duckdb.measure_fixed_compute_demand(
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
  guard @duckdb.fixed_compute_receipt_rows(receipt) is Some(rows) else {
    return Err(InvalidState)
  }
  value.measured = Some(
    match
      @execution.finish_fixed_producer_measurement(value.measurement, rows) {
      Ok(measured) => measured
      Err(issue) => return Err(Guard(issue))
    },
  )
  guard verified_compute_rows(value) is Some(rows) else {
    return Err(Completion(Unverified))
  }
  match @execution.complete_trusted_output(value.port, value) {
    Ok(output) => {
      value.completed_rows = Some(rows)
      value.completed = true
      Ok(output)
    }
    Err(issue) => Err(Completion(issue))
  }
}

///|
pub fn abort_duckdb_compute_attempt(value : DuckDBComputeAttempt) -> Unit {
  if value.completed {
    return
  }
  close_duckdb_compute_attempt(value)
}

///|
pub fn close_duckdb_compute_attempt(value : DuckDBComputeAttempt) -> Unit {
  value.live = false
  value.retained_live.val = false
  if value.join_stream is Some(stream) {
    @execution.cancel_fixed_join_stream(stream)
  }
  for stream in value.input_streams {
    if stream is Some(stream) {
      @duckdb.cancel_fixed_import_stream(stream) |> ignore
    }
  }
  value.input_demand = None
  value.stream_receipt = None
  value.stream_measured = None
  value.stream_demand = None
  value.pending_material = None
  value.completed_rows = None
  if value.receiving is Some(receiving) {
    @duckdb.abort_fixed_compute_receiving(receiving)
  }
  value.receipt = None
  value.measured = None
  value.demand = None
  value.completed = false
}
