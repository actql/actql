///|
/// Installed Local preparation; the dispatch lookup does not interpret its name.
fn prepare_local_dispatch_work(
  host : StrategyHostDispatch,
  task : Int,
  revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
) -> Result[@host_driver.DispatchWork, DispatchIssue] {
  @local_driver.prepare_local_dispatch(
    host.local_module,
    task,
    revision,
    request,
  ).map_err(local_dispatch_issue)
}

///|
/// The connector owns compilation/binding. The Host admits preflight work on
/// its existing ledger before the connector may scan fixed inputs.
fn prepare_native_dispatch_work(
  host : StrategyHostDispatch,
  task : Int,
  revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
) -> Result[@host_driver.DispatchWork, DispatchIssue] {
  if host.native_rejections[task - 1] is Some(_) {
    return Err(ForeignSelection)
  }
  if @strategy.strategy_resident_profile(revision, task) is Some(_) &&
    host.resident_rejections[task - 1] is Some(_) {
    return Err(ForeignSelection)
  }
  let preparation = match
    @duckdb_compute.prepare_duckdb_dispatch_candidate(
      host.registry,
      host.native_registration,
      request,
      host.limits.native_query,
      host.limits.join_validation,
      @strategy.captured_task_join_output_limit(host.run, task),
      host.limits.candidate_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NativeCandidate(issue))
  }
  if @duckdb_compute.duckdb_dispatch_preflight_work(preparation) is Some(work) {
    match
      @resources.charge_planning(@strategy.captured_dag_ledger(host.run), work) {
      Ok(_) => ()
      Err(issue) => return Err(Run(Physical(issue)))
    }
  }
  let selected = match
    @duckdb_compute.bind_duckdb_dispatch_candidate(preparation) {
    Ok(value) => value
    Err(Native(JoinPreparation(issue))) => {
      @strategy.stop_captured_dag(host.run)
      return Err(JoinPreparation(issue))
    }
    Err(Native(issue)) => return Err(NativeCandidate(issue))
    Err(Selection(issue)) => return Err(Candidate(issue))
    Err(NotSelected) => return Err(ForeignSelection)
  }
  @host_driver.stage_dispatch_work(
    host.native_channel,
    task,
    revision,
    request,
    @duckdb_driver.configure_strategy_compute_host(
      host.run,
      task,
      @duckdb_driver.configure_compute_host(
        @duckdb_compute.duckdb_selected_compute_choice(selected),
        @duckdb_compute.duckdb_selected_compute_candidate(selected),
        host.generated[task - 1],
        host.limits.native,
        host.limits.transport,
      ),
    ),
  ).map_err(dispatch_driver_issue)
}

///|
fn local_dispatch_issue(
  issue : @local_driver.LocalDispatchIssue,
) -> DispatchIssue {
  match issue {
    Configuration(_) => InvalidConfiguration
    Preparation(Candidate(issue)) => Candidate(issue)
    Preparation(NotSelected) => ForeignSelection
    Preparation(Capacity) => Run(Physical(InvalidLimits))
    Preparation(Execution(issue)) => Run(Compute(issue))
    Dispatch(issue) => dispatch_driver_issue(issue)
    Execution(issue) => Run(issue)
    Search(issue) => Search(issue)
  }
}
