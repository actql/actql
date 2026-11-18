///|
// Bind the actual configured Run definition, Account and original execution
// context. A program/Plan CID or another equal Values input is not this Run.
fn local_compute_control_authorized(
  host : LocalComputeHost,
  authorization : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  operation : String,
) -> Bool {
  current.account_id() == host.plan.account_id &&
  tuple.principal == host.plan.tuple.principal &&
  tuple.connection == host.plan.tuple.connection &&
  tuple.resource == host.plan.tuple.resource &&
  tuple.operation == operation &&
  @authorization.dispatch_authorization_matches(
    authorization,
    current,
    tuple,
    Activation,
    @publication.publication_contract_identity(host.plan.definition),
    host.plan.execution_context_cid,
  )
}

///|
/// Core pre-work stop-on-entry only. This is not a negotiated public control
/// capability, durable receipt, Run start, task grant or Effect approval.
/// This configured Owner supplies its SAME original graph and run definition.
pub fn prepare_local_compute_task_control(
  host : LocalComputeHost,
  authorization : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
) -> Result[Unit, @strategy.CapturedTaskControlIssue] {
  if !local_compute_control_authorized(
      host, authorization, current, tuple, "pause",
    ) {
    return Err(AuthorizationMismatch)
  }
  let hooks = match prepare_local_compute_task_boundaries(host) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue {
          Resource(resource) => @strategy.Resource(resource)
          Stopped => @strategy.Stopped
          _ => @strategy.AlreadyStarted
        },
      )
  }
  @strategy.prepare_captured_task_control(
    local_compute_run(host),
    hooks,
    authorization,
    current,
    tuple,
    @publication.publication_contract_identity(host.plan.definition),
    host.plan.execution_context_cid,
  )
}

///|
/// Reuse the original task Owner's gate. Actual durable command admission,
/// immutable receipt/lookup and public capability remain a separate supplier.
pub fn command_local_compute_task_control(
  host : LocalComputeHost,
  expected_revision : Int,
  command : @strategy.CapturedTaskControlCommand,
  authorization : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
) -> Result[Unit, @strategy.CapturedTaskControlIssue] {
  if !local_compute_control_authorized(
      host,
      authorization,
      current,
      tuple,
      if command == @strategy.Pause {
        "pause"
      } else {
        "resume"
      },
    ) {
    return Err(AuthorizationMismatch)
  }
  let run = local_compute_run(host)
  guard @strategy.captured_task_boundary_hooks(run) is Some(hooks) else {
    return Err(NotPrepared)
  }
  @strategy.command_captured_task_control(
    run,
    hooks,
    expected_revision,
    command,
    authorization,
    current,
    tuple,
    @publication.publication_contract_identity(host.plan.definition),
    host.plan.execution_context_cid,
  )
}
