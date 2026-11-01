///|
/// Configure the original source-free plan on the installed Host root. This
/// introduces no Source, replacement Ledger, admission or dispatch decision.
pub fn configure_source_free_local_compute_on_ledger(
  plan : LocalRunPlan,
  ledger : @resources.Ledger,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[LocalComputeHost, LocalComputeIssue] {
  if !source_free_profile(plan.prepared) {
    return Err(UnsupportedCapability)
  }
  guard @local.prepare_source_free_local_requirements(
      plan.prepared,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
    )
    is Some(original) else {
    return Err(Configuration)
  }
  guard @local.open_source_free_local_retained_host_on_ledger(
      plan.prepared,
      ledger,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      requirements=Some(original),
    )
    is Some(setup) else {
    return Err(Configuration)
  }
  let run = @driver.dispatch_driver_run(@builtin.configured_host_driver(setup))
  @strategy.require_captured_task_activation(run)
  Ok({ plan, setup, publication: SourceFree(original), })
}

///|
/// Reuse the original task activation's current, subject-bound Account check
/// before configuring physical task resources. This grants no task activation.
pub fn authorize_local_compute_configuration(
  plan : LocalRunPlan,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  context_cid : String,
) -> Result[Unit, LocalComputeIssue] {
  if current.account_id() != plan.account_id ||
    tuple != plan.tuple ||
    context_cid != plan.execution_context_cid ||
    !authorized_input(
      local_run_prepared(plan),
      permit,
      current,
      tuple,
      context_cid,
    ) {
    return Err(AuthorizationMismatch)
  }
  Ok(())
}
