///|
/// Installed Local preparation; the dispatch lookup does not interpret its name.
fn prepare_local_dispatch_work(
  host : StrategyHostDispatch,
  task : Int,
  _revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
) -> Result[DispatchWork, DispatchIssue] {
  match
    @local_connector.prepare_local_module_compute(
      host.local_module,
      task - 1,
      request,
      @strategy.captured_task_join_output_limit(host.run, task).map(limit => {
        (0, limit)
      }),
    ) {
    Ok(compute) => Ok(DispatchWork::Synchronous(compute))
    Err(Candidate(issue)) => Err(Candidate(issue))
    Err(NotSelected) => Err(ForeignSelection)
    Err(Capacity) => Err(Run(Physical(InvalidLimits)))
    Err(Execution(issue)) => Err(Run(Compute(issue)))
  }
}

///|
/// The connector owns compilation/binding. The Host admits preflight work on
/// its existing ledger before the connector may scan fixed inputs.
fn prepare_native_dispatch_work(
  host : StrategyHostDispatch,
  task : Int,
  revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
) -> Result[DispatchWork, DispatchIssue] {
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
  Ok(
    DispatchWork::Native(
      configure_strategy_compute_host(
        host.run,
        task,
        configure_compute_host(
          @duckdb_compute.duckdb_selected_compute_choice(selected),
          @duckdb_compute.duckdb_selected_compute_candidate(selected),
          host.generated[task - 1],
          host.limits.native,
          host.limits.transport,
        ),
      ),
    ),
  )
}
