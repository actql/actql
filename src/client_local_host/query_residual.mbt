///|
pub(all) enum ClientQueryResidualIssue {
  InvalidLimits
  ForeignReceipt
  InputUnavailable
  UnsupportedProgram
  Local(@connector.FixedComputeIssue)
  Input(@execution.ProducerReadIssue)
  Guard(@execution.FixedInputGuardIssue)
  Acquisition(@duckdb_host.BroadHostIssue)
}

///|
struct ClientQueryResidual {
  query : @query.QuerySequence
  receipt : @query.QueryReceipt
  owner : @local.GuardedRelationExecution
  max_rows : Int
  max_value_bytes : Int
  execution_limits : @execution.SequenceExecutionLimits
  measurement_limits : @execution.FixedInputGuardMeasureLimits
}

///|
/// The shared Host supplies the exact configured limits to both execution and
/// capture. No adapter can substitute an unchecked output for this owner.
pub fn complete_client_broad_query_residual(
  residual : ClientQueryResidual,
  issuer : @duckdb_query.DuckDBQueryIssuer,
  attempt : @duckdb_query.DuckDBBroadAttempt,
  limits : @duckdb_query.DuckDBBroadCompletionLimits,
) -> Result[
  @duckdb_query.DuckDBBroadObservation,
  @duckdb_query.DuckDBEvidenceIssue,
] {
  @duckdb_query.complete_duckdb_broad_bounded_capture(
    issuer,
    attempt,
    residual.receipt,
    fn(query, receipt, guards, admitted) {
      verified_client_query_residual(residual, query, receipt, guards, admitted)
    },
    fn() {
      @local.cleanup_managed_provider(client_query_residual_execution(residual))
    },
    limits,
  )
}

///|
fn verified_client_query_residual(
  residual : ClientQueryResidual,
  query : @query.QuerySequence,
  receipt : @query.QueryReceipt,
  guards : @planning.QueryLogicalGuards,
  admitted : @duckdb_query.DuckDBBroadCompletionLimits,
) -> @execution.CompletedOutput? {
  let measured = residual.measurement_limits
  if !physical_equal(residual.execution_limits, admitted.execution) ||
    measured.max_work != admitted.guards.max_work ||
    measured.max_bytes != admitted.guards.max_bytes ||
    measured.max_nodes != admitted.guards.max_nodes ||
    measured.max_depth != admitted.guards.max_depth {
    return None
  }
  client_query_residual_output(
    residual,
    query,
    receipt,
    guards.max_rows,
    guards.max_value_bytes,
  )
}

///|
pub fn client_query_residual_execution(
  residual : ClientQueryResidual,
) -> @local.ManagedProviderExecution {
  @local.guarded_relation_execution(residual.owner)
}

///|
/// Return only the guarded completion for this exact query and receipt.
/// Acquisition still owns transport, issuer and capture admission checks.
pub fn client_query_residual_output(
  residual : ClientQueryResidual,
  query : @query.QuerySequence,
  receipt : @query.QueryReceipt,
  max_rows : Int,
  max_value_bytes : Int,
) -> @execution.CompletedOutput? {
  guard physical_equal(residual.query, query) &&
    physical_equal(residual.receipt, receipt) &&
    residual.max_rows == max_rows &&
    residual.max_value_bytes == max_value_bytes else {
    return None
  }
  @local.guarded_relation_completed_output(residual.owner)
}

///|
pub fn start_client_query_residual(
  query : @query.QuerySequence,
  receipt : @query.QueryReceipt,
  live : () -> Bool,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_output_rows : Int,
  max_value_bytes : Int,
  max_name_bytes~ : Int,
) -> Result[@local.ManagedProviderExecution, ClientQueryResidualIssue] {
  prepare_client_query_residual(
    query,
    receipt,
    live,
    execution,
    measurement,
    max_output_rows,
    max_value_bytes,
    max_name_bytes~,
  ).map(client_query_residual_execution)
}

///|
/// Execute only the already admitted acquisition prefix. The acquisition owner
/// retains source authority and all receipt/capture guards. This returns a
/// normal Local child, not a captured observation or publication authority.
/// Keep `live` tied to that acquisition until the child confirms its stop.
pub fn prepare_client_query_residual(
  query : @query.QuerySequence,
  receipt : @query.QueryReceipt,
  live : () -> Bool,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_output_rows : Int,
  max_value_bytes : Int,
  max_name_bytes~ : Int,
) -> Result[ClientQueryResidual, ClientQueryResidualIssue] {
  if max_output_rows < 0 ||
    max_value_bytes < 0 ||
    max_name_bytes < 0 ||
    execution.max_work < 0 {
    return Err(InvalidLimits)
  }
  if !@query.query_receipt_matches(receipt, query) {
    return Err(ForeignReceipt)
  }
  if !live() {
    return Err(InputUnavailable)
  }
  let measurement_limits = measurement
  let (sequence, measurement) = match
    @execution.prepare_fixed_input_guard_roots(
      @query.query_generated_sequence(query),
      max_value_bytes,
      true,
      measurement,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Guard(issue))
  }
  let read = match
    @execution.prepare_supplied_relation_read(
      @query.query_sequence_owner(query),
      0,
      @query.query_receipt_rows(receipt),
      live,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  @local.prepare_guarded_supplied_relation(
    sequence,
    read,
    execution,
    measurement,
    max_output_rows,
    max_value_bytes,
    max_name_bytes~,
  )
  .map(owner => {
    query,
    receipt,
    owner,
    max_rows: max_output_rows,
    max_value_bytes,
    execution_limits: execution,
    measurement_limits,
  })
  .map_err(issue => Local(issue))
}
