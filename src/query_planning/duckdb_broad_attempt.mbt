///|
pub(all) enum DuckDBBroadAttemptIssue {
  InvalidState
  Metadata(@duckdb.SourceTableIssue)
  Receiving(@duckdb.BroadReceivingIssue)
  Residual(@query.QueryGuardIssue)
  Retention(QueryRetentionIssue)
}

///|
priv enum DuckDBBroadState {
  Metadata
  Table(@duckdb.BroadTable)
  Receiving(@duckdb.BroadReceiving)
  AwaitingCleanup(@execution.CapturedRows)
  Ready(@execution.CapturedRows)
  Completed(DuckDBBroadCompletion)
  Retained(DuckDBBroadRetention)
  Failed
}

///|
priv struct DuckDBBroadCompletion {
  _scan : @execution.CapturedRows
  sequence : @execution.CompletedSequence
}

///|
/// Host-private one-shot acquisition realization. Completion here means the
/// guarded computation is retained, not that observation evidence was issued.
struct DuckDBBroadAttempt {
  preparation : DuckDBQueryPreparation
  mut state : DuckDBBroadState
}

///|
pub fn prepare_duckdb_broad_attempt(
  preparation : DuckDBQueryPreparation,
) -> DuckDBBroadAttempt {
  { preparation, state: Metadata, }
}

///|
pub fn abort_duckdb_broad_attempt(attempt : DuckDBBroadAttempt) -> Unit {
  if attempt.state is Receiving(receiver) {
    @duckdb.abort_broad_receiving(receiver)
  }
  attempt.state = Failed
}

///|
fn[T] fail_duckdb_broad_attempt(
  attempt : DuckDBBroadAttempt,
  issue : DuckDBBroadAttemptIssue,
) -> Result[T, DuckDBBroadAttemptIssue] {
  abort_duckdb_broad_attempt(attempt)
  Err(issue)
}

///|
pub fn admit_duckdb_broad_metadata(
  attempt : DuckDBBroadAttempt,
  rows : Int,
  fields : Array[(String, @duckdb.PhysicalType)],
  columns : Array[@decode.Cursor],
) -> Result[Unit, DuckDBBroadAttemptIssue] {
  guard attempt.state is Metadata else {
    return fail_duckdb_broad_attempt(attempt, InvalidState)
  }
  match
    @duckdb.admit_broad_table(attempt.preparation.broad, rows, fields, columns) {
    Ok(table) => {
      attempt.state = Table(table)
      Ok(())
    }
    Err(issue) => fail_duckdb_broad_attempt(attempt, Metadata(issue))
  }
}

///|
pub fn begin_duckdb_broad_receipt(
  attempt : DuckDBBroadAttempt,
  fields : Array[(String, @duckdb.PhysicalType)],
  physical : @duckdb.PhysicalResultLimits,
  max_metadata_work : Int,
  retention : @execution.ValueLimits,
) -> Result[Unit, DuckDBBroadAttemptIssue] {
  guard attempt.state is Table(table) else {
    return fail_duckdb_broad_attempt(attempt, InvalidState)
  }
  match
    @duckdb.prepare_broad_receiving(
      table, fields, physical, max_metadata_work, retention,
    ) {
    Ok(receiver) => {
      attempt.state = Receiving(receiver)
      Ok(())
    }
    Err(issue) => fail_duckdb_broad_attempt(attempt, Receiving(issue))
  }
}

///|
pub fn accept_duckdb_broad_chunk(
  attempt : DuckDBBroadAttempt,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, DuckDBBroadAttemptIssue] {
  guard attempt.state is Receiving(receiver) else {
    return fail_duckdb_broad_attempt(attempt, InvalidState)
  }
  match @duckdb.accept_broad_chunk(receiver, rows, columns) {
    Ok(_) => Ok(())
    Err(issue) => fail_duckdb_broad_attempt(attempt, Receiving(issue))
  }
}

///|
pub fn finish_duckdb_broad_receipt(
  attempt : DuckDBBroadAttempt,
) -> Result[Unit, DuckDBBroadAttemptIssue] {
  guard attempt.state is Receiving(receiver) else {
    return fail_duckdb_broad_attempt(attempt, InvalidState)
  }
  match @duckdb.finish_broad_receiving(receiver) {
    Ok(input) => {
      attempt.state = AwaitingCleanup(input)
      Ok(())
    }
    Err(issue) => fail_duckdb_broad_attempt(attempt, Receiving(issue))
  }
}

///|
/// Trusted Host calls this only after the same read transaction and all native
/// commands have settled and resource cleanup has succeeded. It is not a
/// serializable transport attestation or permission to issue capture evidence.
pub fn settle_duckdb_broad_transport(
  attempt : DuckDBBroadAttempt,
) -> Result[Unit, DuckDBBroadAttemptIssue] {
  guard attempt.state is AwaitingCleanup(input) else {
    return fail_duckdb_broad_attempt(attempt, InvalidState)
  }
  attempt.state = Ready(input)
  Ok(())
}

///|
pub fn execute_duckdb_broad_attempt(
  attempt : DuckDBBroadAttempt,
  limits : @execution.SequenceExecutionLimits,
  measurement : @query.QueryGuardMeasureLimits,
) -> Result[Unit, DuckDBBroadAttemptIssue] {
  guard attempt.state is Ready(input) else {
    return fail_duckdb_broad_attempt(attempt, InvalidState)
  }
  match
    execute_duckdb_broad_residual(
      attempt.preparation,
      input,
      limits,
      measurement,
    ) {
    Ok((completed, _)) => {
      attempt.state = Completed({ _scan: input, sequence: completed, })
      Ok(())
    }
    Err(issue) => fail_duckdb_broad_attempt(attempt, Residual(issue))
  }
}

///|
/// No pre-cleanup or failed input/result is exposed. This computation is not an
/// acquisition observation; the trusted issuer must still retain and verify it.
pub fn duckdb_broad_attempt_output(
  attempt : DuckDBBroadAttempt,
) -> @execution.CompletedOutput? {
  let completed = match attempt.state {
    Completed(value) => value
    Retained(value) => value.completion
    _ => return None
  }
  @execution.completed_output(
    completed.sequence,
    @acquisition.query_acquisition_capture(
      @query.query_sequence_requirement(
        attempt.preparation.requirement.material.owner,
      ),
    ),
  )
}
