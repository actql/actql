///|
/// This is custody of the existing Local guarded child, not a second executor.
/// The original attempt retains both its scan and child until cleanup succeeds.
priv struct RowCaptureResidual {
  receipt : @query.QueryReceipt
  execution : @local.GuardedRelationExecution
}

///|
fn row_capture_input_live(run : RowRun, receipt : @query.QueryReceipt) -> Bool {
  guard !run.closed &&
    run.issuer is DirectIssuer(issuer) &&
    run.attempt.state is AwaitingCleanup(scan) &&
    physical_equal(scan, @query.query_receipt_rows(receipt)) else {
    return false
  }
  @planning.query_evidence_registration_live(issuer.registration) &&
  @planning.query_evidence_transport_matches(issuer.registration, run.attempt)
}

///|
/// Prepare only the original checked acquisition prefix after physical stop.
/// No downstream JOIN, Model or Effect can execute through this handle.
pub fn begin_row_capture(run : RowRun) -> Result[Unit, RowHostIssue] {
  if run.configuration is InputConfiguration(_) {
    return begin_input_row_capture(run)
  }
  guard !run.closed &&
    run.residual is None &&
    run.configuration is DirectConfiguration(configuration) &&
    run.attempt.state is AwaitingCleanup(scan) else {
    return Err(InvalidState)
  }
  let query = @planning.query_material_owner(
    @planning.query_requirement_material(configuration.requirement),
  )
  let receipt = match @query.bind_query_receipt(query, scan) {
    Ok(value) => value
    Err(issue) => return Err(Attempt(Residual(@query.Execution(issue))))
  }
  if !row_capture_input_live(run, receipt) {
    return Err(Evidence(UnverifiedTransport))
  }
  let guards = @planning.query_requirement_guards(configuration.requirement)
  let configured = configuration.limits.guards
  let (sequence, measurement) = match
    @execution.prepare_fixed_input_guard_roots(
      @query.query_generated_sequence(query),
      guards.max_value_bytes,
      true,
      {
        max_work: configured.max_work,
        max_bytes: configured.max_bytes,
        max_nodes: configured.max_nodes,
        max_depth: configured.max_depth,
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Residual(@connector.Guard(issue)))
  }
  let read = match
    @execution.prepare_supplied_relation_read(
      @query.query_sequence_owner(query),
      @query.query_receipt_input_index(query),
      scan,
      fn() { row_capture_input_live(run, receipt) },
    ) {
    Ok(value) => value
    Err(_) => return Err(Residual(@connector.InputUnavailable))
  }
  let execution = match
    @local.prepare_guarded_supplied_relation(
      sequence,
      read,
      configuration.limits.execution,
      measurement,
      guards.max_rows,
      guards.max_value_bytes,
      max_name_bytes=configuration.limits.records.max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Residual(issue))
  }
  run.residual = Some({ receipt, execution, })
  Ok(())
}

///|
/// Logical work remains the existing managed child's cumulative total. A
/// closed attempt may only observe its requested stop, never capture success.
pub fn advance_row_capture(
  run : RowRun,
  quantum : Int,
) -> Result[(Bool, Int64), RowHostIssue] {
  if run.configuration is InputConfiguration(_) {
    return advance_input_row_capture(run, quantum)
  }
  guard run.residual is Some(residual) else { return Err(InvalidState) }
  let execution = @local.guarded_relation_execution(residual.execution)
  let poll = match @local.advance_managed_provider(execution, quantum) {
    Ok(value) => value
    Err(issue) => {
      abort_row_run(run)
      return Err(Residual(issue))
    }
  }
  let work = match @local.managed_provider_cumulative_work(execution) {
    Ok(value) => value
    Err(issue) => {
      abort_row_run(run)
      return Err(ResidualWork(issue))
    }
  }
  match poll {
    @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) =>
      Ok((false, work))
    @local.Complete(_, ..) => {
      if run.closed || !row_capture_input_live(run, residual.receipt) {
        return Err(InvalidState)
      }
      Ok((true, work))
    }
    @local.Failed(issue, ..) => {
      abort_row_run(run)
      Err(Residual(issue))
    }
    @local.Stopped(..) | @local.CarrierComplete(_, ..) => Err(InvalidState)
  }
}

///|
/// A failed or stopped child remains owned and retryable until cleanup confirms.
/// Do not return its reservation merely because the physical reader has stopped.
pub fn cleanup_row_capture(run : RowRun) -> Result[Bool, RowHostIssue] {
  if run.configuration is InputConfiguration(_) {
    return Ok(cleanup_input_row_capture(run, 64))
  }
  guard run.residual is Some(residual) else {
    return if run.closed && run.physical is None {
      Ok(retire_closed_row_evidence(run.attempt))
    } else {
      Ok(true)
    }
  }
  guard run.closed else { return Ok(false) }
  let result = @local.cleanup_managed_provider(
    @local.guarded_relation_execution(residual.execution),
  ).map_err(issue => RowHostIssue::Residual(issue))
  if result is Ok(true) {
    run.residual = None
    if run.physical is None {
      return Ok(retire_closed_row_evidence(run.attempt))
    }
  }
  result
}

///|
/// Cleanup retry may advance only a child whose original RowRun is closed.
/// The earlier close requested cancellation; no new Compute or capture can
/// start here. Keep the same child and reservation while stop remains pending.
pub fn advance_row_capture_cleanup(
  run : RowRun,
  quantum : Int,
) -> Result[Bool, RowHostIssue] {
  if !run.closed || quantum <= 0 {
    return Err(InvalidState)
  }
  if run.configuration is InputConfiguration(_) {
    return Ok(cleanup_input_row_capture(run, quantum))
  }
  match cleanup_row_capture(run) {
    Ok(true) => return Ok(true)
    Ok(false) => ()
    Err(issue) => return Err(issue)
  }
  guard run.residual is Some(residual) else { return Err(InvalidState) }
  // A stopped reader can still own incremental cleanup. Retry that same
  // cleanup without resuming an already terminal Compute child.
  if @local.managed_provider_stopped(
      @local.guarded_relation_execution(residual.execution),
    ) {
    return Ok(false)
  }
  match
    @local.advance_managed_provider(
      @local.guarded_relation_execution(residual.execution),
      quantum,
    ) {
    Ok(_) => cleanup_row_capture(run)
    Err(issue) => Err(Residual(issue))
  }
}
