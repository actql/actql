///|
pub(all) struct BroadHostLimits {
  physical : @duckdb.PhysicalResultLimits
  metadata_work : Int
  retention : @execution.ValueLimits
  completion : @planning.DuckDBBroadCompletionLimits
  transport : @duckdb.TransportColumnLimits
}

///|
struct BroadHostConfiguration {
  contracts : @planning.QueryEvidenceContracts
  requirement : @planning.QueryRequirement
  choice : @planning.AcquisitionChoice
  candidate : @planning.PreparedAcquisition[@planning.DuckDBQueryPreparation]
  limits : BroadHostLimits
}

///|
struct BroadHostRun {
  configuration : BroadHostConfiguration
  issuer : @planning.DuckDBQueryIssuer
  attempt : @planning.DuckDBBroadAttempt
  scan : @duckdb.BroadScan
  mut closed : Bool
}

///|
pub(all) enum BroadHostIssue {
  InvalidState
  Evidence(@planning.DuckDBEvidenceIssue)
  Attempt(@planning.DuckDBBroadAttemptIssue)
}

///|
/// Captures exact checked ownership, not a serialized replacement or verifier.
pub fn configure_broad_host(
  contracts : @planning.QueryEvidenceContracts,
  requirement : @planning.QueryRequirement,
  choice : @planning.AcquisitionChoice,
  candidate : @planning.PreparedAcquisition[@planning.DuckDBQueryPreparation],
  limits : BroadHostLimits,
) -> BroadHostConfiguration {
  { contracts, requirement, choice, candidate, limits, }
}

///|
pub fn configured_broad_host_limits(
  value : BroadHostConfiguration,
) -> BroadHostLimits {
  value.limits
}

///|
/// Trusted bootstrap only. The standard Node entry owns the verifier installation.
pub fn start_configured_broad_host(
  configuration : BroadHostConfiguration,
  nonce : String,
  verify : (@planning.DuckDBBroadAttempt) -> Bool,
) -> Result[BroadHostRun, BroadHostIssue] {
  let issuer = match
    @planning.prepare_duckdb_query_issuer(
      configuration.contracts,
      configuration.requirement,
      nonce,
      128,
      verify,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let attempt = match
    @planning.prepare_issued_duckdb_broad_attempt(
      issuer,
      configuration.choice,
      configuration.candidate,
    ) {
    Ok(value) => value
    Err(issue) => {
      @planning.close_duckdb_query_issuer(issuer)
      return Err(Evidence(issue))
    }
  }
  // Selection was validated above; retrieve the exact registered payload.
  let preparation = @planning.acquisition_choice_payload(
    configuration.choice,
    configuration.candidate,
  ).unwrap()
  Ok({
    configuration,
    issuer,
    attempt,
    scan: @planning.duckdb_query_broad_scan(preparation),
    closed: false,
  })
}

///|
pub fn broad_host_attempt(run : BroadHostRun) -> @planning.DuckDBBroadAttempt {
  run.attempt
}

///|
pub fn broad_host_scan(run : BroadHostRun) -> @duckdb.BroadScan {
  run.scan
}

///|
pub fn broad_host_metadata(
  run : BroadHostRun,
  rows : Int,
  fields : Array[(String, @duckdb.PhysicalType)],
  columns : Array[@decode.Cursor],
) -> Result[Unit, BroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  @planning.admit_duckdb_broad_metadata(run.attempt, rows, fields, columns).map_err(issue => {
      Attempt(issue)
    },
  )
}

///|
pub fn begin_broad_host_receipt(
  run : BroadHostRun,
  fields : Array[(String, @duckdb.PhysicalType)],
) -> Result[Unit, BroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  let limits = run.configuration.limits
  @planning.begin_duckdb_broad_receipt(
    run.attempt,
    fields,
    limits.physical,
    limits.metadata_work,
    limits.retention,
  ).map_err(issue => Attempt(issue))
}

///|
pub fn accept_broad_host_chunk(
  run : BroadHostRun,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, BroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  @planning.accept_duckdb_broad_chunk(run.attempt, rows, columns).map_err(issue => {
    Attempt(issue)
  })
}

///|
pub fn finish_broad_host_receipt(
  run : BroadHostRun,
) -> Result[Unit, BroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  @planning.finish_duckdb_broad_receipt(run.attempt).map_err(issue => {
    Attempt(issue)
  })
}

///|
pub fn complete_broad_host(
  run : BroadHostRun,
) -> Result[@planning.DuckDBBroadObservation, BroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  @planning.complete_duckdb_broad_capture(
    run.issuer,
    run.attempt,
    run.configuration.limits.completion,
  ).map_err(issue => Evidence(issue))
}

///|
pub fn bind_broad_host_input(
  run : BroadHostRun,
  observation : @planning.DuckDBBroadObservation,
  receiver : @lower.BoundPrepared,
  input_index : Int,
) -> Result[@execution.BoundProducerInput, BroadHostIssue] {
  if run.closed {
    return Err(InvalidState)
  }
  let producer = @query.query_sequence_owner(
    @planning.query_material_owner(
      @planning.query_requirement_material(run.configuration.requirement),
    ),
  )
  @planning.bind_captured_duckdb_broad_input(
    run.issuer,
    run.attempt,
    observation,
    receiver,
    input_index,
    producer,
  ).map_err(issue => Evidence(issue))
}

///|
pub fn abort_broad_host(run : BroadHostRun) -> Unit {
  @planning.abort_duckdb_broad_attempt(run.attempt)
}

///|
pub fn close_broad_host(run : BroadHostRun) -> Unit {
  if !run.closed {
    abort_broad_host(run)
    @planning.close_duckdb_query_issuer(run.issuer)
    run.closed = true
  }
}
