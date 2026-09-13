///|
/// Trusted Host-owned orchestration. No fixed Program, catalog or test exports
/// belong here. The Node assembly supplies only its private transport verifier.
struct NativeHostRun {
  issuer : @planning.DuckDBNativeIssuer
  attempt : @planning.DuckDBNativeAttempt
  scan : @duckdb.NativeScan
  mut port : @duckdb.NativeReceiptPort?
  mut observation : @planning.DuckDBNativeObservation?
  mut closed : Bool
}

///|
pub(all) enum NativeHostIssue {
  InvalidState
  Evidence(@planning.DuckDBEvidenceIssue)
  Attempt(@planning.DuckDBNativeAttemptIssue)
  Completion(@execution.TrustedOutputIssue)
  Binding(@execution.ProducerBindingIssue)
}

///|
/// Trusted bootstrap, not ordinary Connector registration. The standard Node
/// entry must install its settlement verifier without a Program-level override.
pub fn start_native_host(
  contract : @planning.QueryTwoReceiptContract,
  requirement : @planning.QueryRequirement,
  choice : @planning.AcquisitionChoice,
  candidate : @planning.PreparedAcquisition[@planning.DuckDBNativePreparation],
  nonce : String,
  max_nonce_chars : Int,
  physical : @duckdb.PhysicalResultLimits,
  metadata_work : Int,
  measurement : @execution.FixedInputGuardMeasureLimits,
  verify_transport : (@planning.DuckDBNativeAttempt) -> Bool,
) -> Result[NativeHostRun, NativeHostIssue] {
  let issuer = match
    @planning.prepare_duckdb_native_issuer(
      contract, requirement, nonce, max_nonce_chars, verify_transport,
    ) {
    Ok(issuer) => issuer
    Err(issue) => return Err(Evidence(issue))
  }
  let attempt = match
    @planning.prepare_issued_duckdb_native_attempt(
      issuer, choice, candidate, physical, metadata_work, measurement,
    ) {
    Ok(attempt) => attempt
    Err(issue) => {
      @planning.close_duckdb_native_issuer(issuer)
      return Err(Evidence(issue))
    }
  }
  Ok({
    issuer,
    attempt,
    scan: @planning.duckdb_native_preparation_scan(
      @planning.duckdb_native_attempt_preparation(attempt),
    ),
    port: None,
    observation: None,
    closed: false,
  })
}

///|
pub fn native_host_attempt(
  run : NativeHostRun,
) -> @planning.DuckDBNativeAttempt {
  run.attempt
}

///|
pub fn native_host_scan(run : NativeHostRun) -> @duckdb.NativeScan {
  run.scan
}

///|
pub fn abort_native_host(run : NativeHostRun) -> Unit {
  if run.observation is None {
    @planning.abort_duckdb_native_attempt(run.attempt)
  }
  run.port = None
}

///|
pub fn close_native_host(run : NativeHostRun) -> Unit {
  if run.closed {
    return
  }
  abort_native_host(run)
  @planning.close_duckdb_native_issuer(run.issuer)
  run.closed = true
}

///|
fn can_receive(run : NativeHostRun) -> Bool {
  !run.closed && run.observation is None
}

///|
pub fn native_host_metadata(
  run : NativeHostRun,
  rows : Int,
  fields : Array[(String, @duckdb.PhysicalType)],
  columns : Array[@decode.Cursor],
) -> Result[Unit, NativeHostIssue] {
  if !can_receive(run) {
    return Err(InvalidState)
  }
  @planning.admit_duckdb_native_metadata(run.attempt, rows, fields, columns).map_err(issue => {
      Attempt(issue)
    },
  )
}

///|
pub fn begin_native_host_receipt(
  run : NativeHostRun,
  role : @duckdb.NativeReceiptRole,
  fields : Array[(String, @duckdb.PhysicalType)],
) -> Result[Unit, NativeHostIssue] {
  if !can_receive(run) {
    return Err(InvalidState)
  }
  if run.port is Some(_) {
    abort_native_host(run)
    return Err(InvalidState)
  }
  match @planning.begin_duckdb_native_receipt(run.attempt, role, fields) {
    Ok(port) => {
      run.port = Some(port)
      Ok(())
    }
    Err(issue) => Err(Attempt(issue))
  }
}

///|
pub fn accept_native_host_chunk(
  run : NativeHostRun,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, NativeHostIssue] {
  if !can_receive(run) {
    return Err(InvalidState)
  }
  guard run.port is Some(port) else {
    abort_native_host(run)
    return Err(InvalidState)
  }
  @planning.accept_duckdb_native_chunk(run.attempt, port, rows, columns).map_err(issue => {
      Attempt(issue)
    },
  )
}

///|
pub fn finish_native_host_receipt(
  run : NativeHostRun,
) -> Result[Unit, NativeHostIssue] {
  if !can_receive(run) {
    return Err(InvalidState)
  }
  guard run.port is Some(port) else {
    abort_native_host(run)
    return Err(InvalidState)
  }
  run.port = None
  @planning.finish_duckdb_native_receipt(run.attempt, port).map_err(issue => {
    Attempt(issue)
  })
}

///|
pub fn complete_native_host(
  run : NativeHostRun,
  limits : @planning.DuckDBNativeCompletionLimits,
) -> Result[@planning.DuckDBNativeObservation, NativeHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  match
    @planning.complete_duckdb_native_capture(run.issuer, run.attempt, limits) {
    Ok(observation) => {
      run.observation = Some(observation)
      Ok(observation)
    }
    Err(issue) => Err(Evidence(issue))
  }
}

///|
pub fn verify_native_host(
  run : NativeHostRun,
  observation : @planning.DuckDBNativeObservation,
) -> Bool {
  !run.closed &&
  @planning.verify_duckdb_native_observation(
    run.issuer,
    run.attempt,
    observation,
  )
  is Ok(_)
}

///|
pub fn native_host_output(
  run : NativeHostRun,
  observation : @planning.DuckDBNativeObservation,
  max_rows : Int,
  retention : @execution.ValueLimits,
) -> Result[@planning.DuckDBNativeOutput, NativeHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  @planning.materialize_duckdb_native_output(
    run.issuer,
    run.attempt,
    observation,
    max_rows,
    retention,
  ).map_err(issue => Evidence(issue))
}

///|
pub fn bind_native_host_input(
  run : NativeHostRun,
  observation : @planning.DuckDBNativeObservation,
  receiver : @lower.BoundPrepared,
  input_index : Int,
  max_rows : Int,
  retention : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[@execution.BoundProducerInput, NativeHostIssue] {
  let retained = match
    native_host_output(run, observation, max_rows, retention) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let completed = match
    @planning.complete_duckdb_native_output(
      retained, max_entries, max_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Completion(issue))
  }
  @execution.bind_completed_input(
    receiver,
    input_index,
    @duckdb.native_query_owner(@duckdb.native_scan_query(run.scan)),
    completed,
  ).map_err(issue => Binding(issue))
}
