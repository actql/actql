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
  Estimate(@driver.AdaptiveEstimateIssue[@strategy.RunIssue])
  Start(LocalRunIssue)
  StartNotPermitted
}

///|
pub fn configure_source_free_local_compute(
  plan : LocalRunPlan,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[LocalComputeHost, LocalComputeIssue] {
  configure_local_compute(
    plan,
    None,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// The exact verified acquisition remains borrowed from its existing Owner.
/// Opening Compute cannot issue a replacement Source or authorize physical I/O.
pub fn configure_captured_source_local_compute(
  plan : LocalRunPlan,
  source : @query.CapturedInputSource,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[LocalComputeHost, LocalComputeIssue] {
  configure_local_compute(
    plan,
    Some(source),
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Keep Source, transfer and Compute reservations on the installed existing
/// root Ledger. Current Run/task authorization remains unchanged.
pub fn configure_captured_source_local_compute_on_ledger(
  plan : LocalRunPlan,
  source : @query.CapturedInputSource,
  ledger : @resources.Ledger,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[LocalComputeHost, LocalComputeIssue] {
  if !captured_source_profile(plan.prepared) {
    return Err(UnsupportedCapability)
  }
  guard @local.open_captured_local_retained_host_on_ledger(
      plan.prepared,
      source,
      ledger,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
    )
    is Some(setup) else {
    return Err(Configuration)
  }
  let run = @driver.dispatch_driver_run(@builtin.configured_host_driver(setup))
  @strategy.require_captured_task_activation(run)
  Ok({ plan, setup, })
}

///|
fn configure_local_compute(
  plan : LocalRunPlan,
  source : @query.CapturedInputSource?,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[LocalComputeHost, LocalComputeIssue] {
  let prepared = local_run_prepared(plan)
  let unsupported = match source {
    None => !source_free_profile(prepared)
    Some(_) => !captured_source_profile(prepared)
  }
  if unsupported {
    return Err(UnsupportedCapability)
  }
  let opened = match source {
    None =>
      @local.open_source_free_local_retained_host(
        prepared,
        installed_contracts,
        values_body,
        1L,
        0L,
        0L,
        0L,
        fragment_body~,
        ordered_body~,
      )
    Some(source) =>
      @local.open_captured_local_retained_host(
        prepared,
        source,
        installed_contracts,
        values_body,
        1L,
        0L,
        0L,
        0L,
        fragment_body~,
        ordered_body~,
      )
  }
  guard opened is Some(setup) else { return Err(Configuration) }
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
    confirm_local_run_physical_start(
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
    Ok(start) => bind_local_compute_start(host, start)
    Err(StartNotPermitted) => Err(StartNotPermitted)
    Err(issue) => Err(Start(issue))
  }
}

///|
/// A captured Source is configured after the original pre-I/O start decision.
/// Do not reassert that the Run remains physically unstarted at this boundary.
pub fn bind_local_compute_start(
  host : LocalComputeHost,
  start : LocalRunPhysicalStart,
) -> Result[LocalComputeStart, LocalComputeIssue] {
  if !physical_equal(host.plan, start.plan) {
    return Err(StartNotPermitted)
  }
  Ok({ host, })
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
  if !physical_equal(start.host, host) {
    return Err(AuthorizationMismatch)
  }
  match
    authorize_local_compute_configuration(
      host.plan,
      permit,
      current,
      tuple,
      context_cid,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let run = local_compute_run(host)
  match
    @driver.refresh_compute_host(@builtin.configured_host_runtime(host.setup)) {
    Ok(_) => ()
    Err(issue) => return Err(Estimate(issue))
  }
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
  let dispatch = if captured_source_profile(local_run_prepared(host.plan)) {
    guard @builtin.configured_local_module(
        @builtin.configured_host_modules(host.setup),
      )
      is Some(installed) else {
      return Err(UnsupportedCapability)
    }
    let available = []
    let mut index = 0
    for producer in @strategy.captured_next_managed_producers(run) {
      if producer == 0 {
        available.push(@managed.local_managed_captured_relation_input())
      } else if producer == -1 {
        available.push(@managed.local_managed_supplied_relation_input())
      } else if index < completed.length() {
        available.push(@managed.local_managed_relation_output(completed[index]))
        index += 1
      } else {
        return Err(UnsupportedCapability)
      }
    }
    if index != completed.length() {
      return Err(UnsupportedCapability)
    }
    @managed.prepare_local_managed_dispatch_with_outputs(
      installed, available, obligations, 0L,
    ).map_err(issue => Managed(issue))
  } else {
    @builtin.dispatch_managed_local(
      @builtin.configured_host_modules(host.setup),
      completed,
      obligations,
      0L,
    ).map_err(issue => Dispatch(issue))
  }
  let configuration = match dispatch {
    Ok(Some(value)) => value
    Ok(None) => return Err(UnsupportedCapability)
    Err(issue) => return Err(issue)
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
