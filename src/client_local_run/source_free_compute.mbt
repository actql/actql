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
  // The installed root already bounds actual provider, import and output
  // admission. A simultaneous whole-graph estimate is not a start condition.
  guard @local.prepare_source_free_runtime_requirements(
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
/// Attach the existing adopted Model module only after acceptance of this
/// exact Run start. Task activation still requires its own current authority.
pub fn configure_local_source_free_model_compute(
  plan : LocalRunPlan,
  start : LocalRunPhysicalStart,
  adopted : @local.ClientInstalledManagedRun,
  model : @local.ClientInstalledManagedModelPlan,
) -> Result[LocalComputeHost, LocalComputeIssue] {
  if !physical_equal(start.plan, plan) {
    return Err(StartNotPermitted)
  }
  guard @local.open_installed_model_source_free_compute(
      adopted,
      model,
      plan.prepared,
      plan.request,
      plan.compiled,
      plan.definition,
    )
    is Ok(Some(setup)) else {
    return Err(Configuration)
  }
  let run = @driver.dispatch_driver_run(@builtin.configured_host_driver(setup))
  @strategy.require_captured_task_activation(run)
  Ok({ plan, setup, publication: SourceFreeModel(adopted), })
}

///|
/// Configure the adopted Model against the exact acquired input of this Run.
pub fn configure_local_whole_source_model_compute(
  plan : LocalRunPlan,
  start : LocalRunPhysicalStart,
  adopted : @local.ClientInstalledManagedRun,
  model : @local.ClientInstalledManagedModelPlan,
  source : @query.CapturedInputSource,
) -> Result[LocalComputeHost, LocalComputeIssue] {
  guard physical_equal(start.plan, plan) else { return Err(StartNotPermitted) }
  let (setup, run, _) = match @local.open_installed_model_whole_source_compute(
      adopted, model, plan.prepared, plan.request, plan.compiled,
      plan.definition, source,
    ) {
    Ok(opened) => opened
    Err(Run(issue)) => return Err(Task(issue))
    Err(_) => return Err(Configuration)
  }
  @strategy.require_captured_task_activation(run)
  Ok({ plan, setup, publication: WholeSourceModel(adopted), })
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
