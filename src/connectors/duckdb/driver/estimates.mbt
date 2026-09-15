///|
struct DuckDBEstimateModule {
  installed : DuckDBDispatchModule
  configuration : DuckDBEstimateConfiguration
}

///|
priv struct DuckDBEstimateConfiguration {
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
    configuration: {
      schedules: schedules.copy(),
      capacities: capacities.copy(),
      max_work,
    },
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
  estimate_duckdb_configuration(
    policy.installed,
    policy.configuration,
    task,
    quantities,
  )
}

///|
fn estimate_duckdb_configuration(
  installed : DuckDBDispatchModule,
  configuration : DuckDBEstimateConfiguration,
  task : Int,
  quantities : @host.TaskEstimateQuantities,
) -> Result[Array[@strategy.TaskOffer], DuckDBEstimateIssue] {
  guard task > 0 && configuration.schedules.get(task - 1) is Some(schedule) else {
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
      configuration.capacities[task - 1],
      configuration.max_work,
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
        configuration.capacities[task - 1],
        configuration.max_work,
        resident=resident.profile,
      ) {
      Ok(value) => offers.push(value)
      Err(issue) => return Err(Search(issue))
    }
  }
  Ok(offers)
}

///|
pub fn install_duckdb_dispatch_estimates(
  installed : DuckDBDispatchModule,
  policy : DuckDBEstimateModule,
) -> Result[Unit, DuckDBEstimateIssue] {
  if installed.estimate_configuration is Some(_) ||
    !physical_equal(installed, policy.installed) ||
    @strategy.strategy_history_count(installed.run) != 0 {
    return Err(InvalidConfiguration)
  }
  installed.estimate_configuration = Some(policy.configuration)
  Ok(())
}

///|
pub fn estimate_duckdb_installed_offers(
  installed : DuckDBDispatchModule,
  task : Int,
  quantities : @host.TaskEstimateQuantities,
) -> Result[Array[@strategy.TaskOffer], DuckDBEstimateIssue] {
  guard installed.estimate_configuration is Some(configuration) else {
    return Err(InvalidConfiguration)
  }
  estimate_duckdb_configuration(installed, configuration, task, quantities)
}
