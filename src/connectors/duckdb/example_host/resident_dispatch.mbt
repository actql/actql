///|
pub fn dispatch_resident_inputs(
  host : StrategyHostDispatch,
  task : Int,
) -> Array[(Int, Int64, Int, Int)]? {
  @host_driver.compute_host_resident_inputs(host.runtime, task)
}

///|
/// Install finite resident alternatives before the first dispatch. Rates cover
/// task work only; the profile adds shared preparation/import/cleanup separately.
pub fn configure_resident_dispatch(
  host : StrategyHostDispatch,
  profile : @strategy.ResidentProfile,
  rates : Array[Array[@cost.WorkRate]],
) -> Result[Unit, DispatchIssue] {
  if @host_driver.dispatch_driver_pending(host.driver) ||
    @strategy.strategy_history_count(host.run) != 0 ||
    rates.length() !=
    @strategy.graph_task_count(@strategy.captured_dag_graph(host.run)) - 1 ||
    !@strategy.resident_profile_matches(host.run, profile) ||
    !physical_equal(
      @strategy.resident_profile_registration(profile),
      host.native_registration,
    ) {
    return Err(InvalidConfiguration)
  }
  let schedules = []
  for row in rates {
    match
      @resources.charge_planning(
        @strategy.captured_dag_ledger(host.run),
        row.length(),
      ) {
      Err(issue) => return Err(Run(Physical(issue)))
      Ok(_) => ()
    }
    for rate in row {
      for
        value in [
          rate.fixed_ms,
          rate.per_row_ms,
          rate.per_wire_byte_ms,
          rate.per_pair_ms,
        ] {
        if value is Some(value) && value < 0L {
          return Err(InvalidConfiguration)
        }
      }
    }
    match
      @cost.prepare_rate_schedule(
        @builtin.duckdb_resource_work_slots(),
        row,
        host.limits.candidate_work,
      ) {
      Ok(schedule) => schedules.push(schedule)
      Err(issue) => return Err(dispatch_rate_issue(issue))
    }
  }
  let policy = match
    @builtin.prepare_duckdb_resource_policy(host.modules, {
      profile,
      schedules,
    }) {
    Ok(value) => value
    Err(issue) => return Err(configured_dispatch_issue(issue))
  }
  @builtin.install_configured_estimate_policy(policy).map_err(unwrap_issue)
}
