///|
/// Installed existing task Owners for the original compiled plan. Configuration
/// performs no physical dispatch. The Host must durably reserve and claim the
/// exact Run through its start Owner before calling the task activation entry.
pub struct LocalComputeHost {
  plan : LocalRunPlan
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue]
}

///|
/// The existing Run start Owner's accepted physical-start decision, bound to
/// this exact configured Host. It is not a new admission or recovery record.
pub struct LocalComputeStart {
  host : LocalComputeHost
}

///|
pub(all) enum LocalComputeIssue {
  AuthorizationMismatch
  UnsupportedCapability
  Configuration
  Task(@strategy.RunIssue)
  Obligations(@execution.ManagedObligationIssue)
  Dispatch(@builtin.ConfiguredDispatchIssue[@strategy.RunIssue])
  Managed(@managed.LocalDispatchIssue)
  Start(LocalRunIssue)
  StartNotPermitted
}

///|
pub fn configure_source_free_local_compute(
  plan : LocalRunPlan,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[LocalComputeHost, LocalComputeIssue] {
  let prepared = @input.local_prepared_program(plan.input)
  if !source_free_profile(prepared) {
    return Err(UnsupportedCapability)
  }
  guard @local.open_source_free_local_retained_host(
      prepared,
      registry_body,
      values_body,
      1L,
      0L,
      0L,
      0L,
      fragment_body~,
      ordered_body~,
    )
    is Some(setup) else {
    return Err(Configuration)
  }
  let run = @driver.dispatch_driver_run(@builtin.configured_host_driver(setup))
  @strategy.require_captured_task_activation(run)
  Ok({ plan, setup, })
}

///|
pub fn local_compute_run(host : LocalComputeHost) -> @strategy.CapturedDAG {
  @driver.dispatch_driver_run(@builtin.configured_host_driver(host.setup))
}

///|
/// The checked DAG chooses the next exact task and producer occurrences.
/// Absence of a ready task does not prove Run success or publication.
pub fn local_compute_producers(host : LocalComputeHost) -> Array[Int] {
  @strategy.captured_next_managed_producers(local_compute_run(host))
}

///|
/// The trusted physical Host supplies facts from its durable original journal.
/// Only the existing Run start Owner decides whether physical work may begin.
pub fn confirm_local_compute_start(
  host : LocalComputeHost,
  retained : @host.ClientRequestIdentity,
  retained_definition_cid : String,
  reserved : Bool,
  physically_unstarted : Bool,
  cancellation_requested : Bool,
  pre_start_failure_confirmed : Bool,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  context_cid : String,
) -> Result[LocalComputeStart, LocalComputeIssue] {
  match
    prepare_local_run_physical_start(
      host.plan,
      retained,
      retained_definition_cid,
      reserved,
      physically_unstarted,
      cancellation_requested,
      pre_start_failure_confirmed,
      permit,
      current,
      tuple,
      context_cid,
    ) {
    Ok(true) => Ok({ host, })
    Ok(false) => Err(StartNotPermitted)
    Err(issue) => Err(Start(issue))
  }
}

///|
/// No Host-side task counter, execution loop or parallel recovery decision.
/// Each activation evaluates the current subject-bound authorization and
/// consumes the existing task Owner's revision-bound, single-use grant.
pub fn start_local_compute_task(
  host : LocalComputeHost,
  start : LocalComputeStart,
  completed : Array[@execution.ManagedCompletedOutput[Int]],
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  context_cid : String,
) -> Result[@managed.LocalManagedDispatchOperations[Int]?, LocalComputeIssue] {
  let plan = host.plan
  if !physical_equal(start.host, host) ||
    current.account_id() != plan.account_id ||
    tuple != plan.tuple ||
    context_cid != plan.execution_context_cid ||
    !authorized_input(
      @input.local_prepared_program(plan.input),
      permit,
      current,
      tuple,
      context_cid,
    ) {
    return Err(AuthorizationMismatch)
  }
  let run = local_compute_run(host)
  guard @strategy.next_captured_task(run) is Some(task) else { return Ok(None) }
  let obligations = match
    @strategy.captured_next_managed_obligations(
      run,
      @driver.compute_host_max_entries(
        @builtin.configured_host_runtime(host.setup),
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Obligations(issue))
  }
  let configuration = match
    @builtin.dispatch_managed_local(
      @builtin.configured_host_modules(host.setup),
      completed,
      obligations,
      0L,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(UnsupportedCapability)
    Err(issue) => return Err(Dispatch(issue))
  }
  let grant = @strategy.task_activation_authorized(
    @authorization.dispatch_authorization_action(permit),
  ).unwrap()
  match @strategy.authorize_captured_task_activation(run, task, grant) {
    Ok(_) => ()
    Err(issue) => return Err(Task(issue))
  }
  @managed.start_local_managed_dispatch_node(configuration)
  .map(value => Some(value))
  .map_err(issue => Managed(issue))
}
