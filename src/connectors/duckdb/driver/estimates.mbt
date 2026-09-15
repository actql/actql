///|
struct DuckDBEstimateModule {
  installed : DuckDBDispatchModule
  schedules : Array[@cost.RateSchedule]
  capacities : Array[@strategy.PhysicalEnvelope]
  max_work : Int
}

///|
priv struct DuckDBResidentEstimates {
  profile : @strategy.ResidentProfile
  schedules : Array[@cost.RateSchedule]
}

///|
pub(all) enum DuckDBEstimateIssue {
  InvalidConfiguration
  Rate(@cost.RateIssue)
  Search(@strategy.SearchIssue)
}

///|
pub fn prepare_duckdb_estimate_module(
  installed : DuckDBDispatchModule,
  schedules : Array[@cost.RateSchedule],
  capacities : Array[@strategy.PhysicalEnvelope],
  max_work : Int,
) -> Result[DuckDBEstimateModule, DuckDBEstimateIssue] {
  if max_work < 0 ||
    schedules.length() > max_work ||
    schedules.length() != installed.sequences.length() ||
    capacities.length() != schedules.length() {
    return Err(InvalidConfiguration)
  }
  for cap in capacities {
    if cap.transfer_bytes < 0L ||
      cap.execution_bytes < 0L ||
      cap.retained_bytes < 0L {
      return Err(InvalidConfiguration)
    }
  }
  Ok({
    installed,
    schedules: schedules.copy(),
    capacities: capacities.copy(),
    max_work,
  })
}

///|
pub fn install_duckdb_resident_estimates(
  installed : DuckDBDispatchModule,
  profile : @strategy.ResidentProfile,
  schedules : Array[@cost.RateSchedule],
) -> Result[Unit, DuckDBEstimateIssue] {
  if installed.resident_estimates is Some(_) ||
    schedules.length() > installed.limits.candidate_work ||
    @strategy.strategy_history_count(installed.run) != 0 ||
    schedules.length() != installed.sequences.length() ||
    !@strategy.resident_profile_matches(installed.run, profile) ||
    !physical_equal(
      @strategy.resident_profile_registration(profile),
      installed.registration,
    ) {
    return Err(InvalidConfiguration)
  }
  installed.resident_estimates = Some({ profile, schedules: schedules.copy(), })
  Ok(())
}

///|
pub fn duckdb_resident_estimates_installed(
  installed : DuckDBDispatchModule,
) -> Bool {
  installed.resident_estimates is Some(_)
}

///|
pub fn estimate_duckdb_module_offers(
  policy : DuckDBEstimateModule,
  task : Int,
  quantities : @host.TaskEstimateQuantities,
) -> Result[Array[@strategy.TaskOffer], DuckDBEstimateIssue] {
  let installed = policy.installed
  guard task > 0 && policy.schedules.get(task - 1) is Some(schedule) else {
    return Err(InvalidConfiguration)
  }
  if duckdb_dispatch_rejection(installed, task) is Some(_) {
    return Ok([])
  }
  let lines = match
    @cost.evaluate_rate_schedule(
      schedule,
      quantities.rows,
      quantities.wire_bytes,
      quantities.pairs,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Rate(issue))
  }
  let base = match
    estimate_duckdb_task_offer(
      installed.run,
      task,
      installed.registration,
      lines,
      policy.capacities[task - 1],
      policy.max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Search(issue))
  }
  let offers = [base]
  if installed.resident_estimates is Some(resident) &&
    duckdb_dispatch_rejection(installed, task, resident=true) is None {
    let lines = match
      @cost.evaluate_rate_schedule(
        resident.schedules[task - 1],
        quantities.rows,
        quantities.wire_bytes,
        quantities.pairs,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Rate(issue))
    }
    match
      estimate_duckdb_task_offer(
        installed.run,
        task,
        installed.registration,
        lines,
        policy.capacities[task - 1],
        policy.max_work,
        resident=resident.profile,
      ) {
      Ok(value) => offers.push(value)
      Err(issue) => return Err(Search(issue))
    }
  }
  Ok(offers)
}
