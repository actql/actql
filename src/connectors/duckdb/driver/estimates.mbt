///|
pub(all) struct DuckDBEstimateSettings {
  schedules : Array[@cost.RateSchedule]
  capacities : Array[@strategy.PhysicalEnvelope]
  max_work : Int
}

///|
pub fn prepare_duckdb_estimate_settings(
  installed : DuckDBDispatchModule,
  settings : DuckDBEstimateSettings,
) -> Result[DuckDBEstimateModule, DuckDBEstimateIssue] {
  prepare_duckdb_estimate_module(
    installed,
    settings.schedules,
    settings.capacities,
    settings.max_work,
  )
}

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
  // A policy can emit offers before installation. Freeze the representation
  // now so an already emitted row offer cannot later authorize file execution.
  installed.output_policy_sealed = true
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
  match validate_duckdb_resident_estimates(installed, profile, schedules) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  installed.resident_estimates.push({ profile, schedules: schedules.copy(), })
  Ok(())
}

///|
fn validate_duckdb_resident_estimates(
  installed : DuckDBDispatchModule,
  profile : @strategy.ResidentProfile,
  schedules : Array[@cost.RateSchedule],
) -> Result[Unit, DuckDBEstimateIssue] {
  if installed.resident_estimates.length() >= installed.limits.candidate_work ||
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
  for existing in installed.resident_estimates {
    if physical_equal(
        @strategy.resident_profile_resource_binding(existing.profile),
        @strategy.resident_profile_resource_binding(profile),
      ) {
      return Err(InvalidConfiguration)
    }
  }
  Ok(())
}

///|
pub(all) struct DuckDBResourceEstimateSettings {
  profile : @strategy.ResidentProfile
  schedules : Array[@cost.RateSchedule]
}

///|
struct DuckDBResourceEstimatePolicy {
  installed : DuckDBDispatchModule
  profile : @strategy.ResidentProfile
  schedules : Array[@cost.RateSchedule]
}

///|
pub fn prepare_duckdb_resource_estimate_settings(
  installed : DuckDBDispatchModule,
  settings : DuckDBResourceEstimateSettings,
) -> Result[DuckDBResourceEstimatePolicy, DuckDBEstimateIssue] {
  match
    validate_duckdb_resident_estimates(
      installed,
      settings.profile,
      settings.schedules,
    ) {
    Err(issue) => Err(issue)
    Ok(_) =>
      Ok({
        installed,
        profile: settings.profile,
        schedules: settings.schedules.copy(),
      })
  }
}

///|
pub fn install_duckdb_resource_estimate_policy(
  installed : DuckDBDispatchModule,
  policy : DuckDBResourceEstimatePolicy,
) -> Result[Unit, DuckDBEstimateIssue] {
  if !physical_equal(installed, policy.installed) {
    return Err(InvalidConfiguration)
  }
  install_duckdb_resident_estimates(installed, policy.profile, policy.schedules)
}

///|
pub fn duckdb_resident_estimates_installed(
  installed : DuckDBDispatchModule,
) -> Bool {
  !installed.resident_estimates.is_empty()
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
      retained_output?=installed.retained_output,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Search(issue))
  }
  let offers = [base]
  if duckdb_dispatch_rejection(installed, task, resident=true) is Some(_) {
    return Ok(offers)
  }
  // A streamed fresh task holds completion metadata plus its file. A resident
  // alternative additionally needs the DB-copy ceiling checked at start. Do
  // not inflate the fresh envelope merely because resident offers are enabled.
  let capacity = configuration.capacities[task - 1]
  let resident_capacity = if installed.retained_output is Some(_) {
    guard @compute.duckdb_task_retention_capacity(installed.limits.execution)
      is Some(copy_bytes) else {
      return Err(InvalidConfiguration)
    }
    {
      ..capacity,
      retained_bytes: Int64::max(capacity.retained_bytes, copy_bytes),
    }
  } else {
    capacity
  }
  for resident in installed.resident_estimates {
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
        resident_capacity,
        configuration.max_work,
        resident=resident.profile,
        retained_output?=installed.retained_output,
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

///|
/// Reuse the installed native rate schedule for one managed candidate. Exact
/// retained row counts are available without opening a representation. Wire
/// bytes remain unknown unless another contract establishes them, so any rate
/// depending on that quantity remains Unknown rather than becoming zero.
fn[T] duckdb_managed_estimate_lines(
  installed : DuckDBDispatchModule,
  task : Int,
  inputs : Array[@execution.ManagedProducerRead[T]],
) -> Result[Array[@cost.SerialEstimateLine], DuckDBEstimateIssue] {
  guard task > 0 else { return Err(InvalidConfiguration) }
  guard installed.estimate_configuration is Some(configuration) else {
    return Ok([
      {
        work_slots: Array::makei(duckdb_dispatch_work_slots(), index => index),
        milliseconds: None,
      },
    ])
  }
  guard configuration.schedules.get(task - 1) is Some(schedule) else {
    return Err(InvalidConfiguration)
  }
  let quantities = @host.managed_task_estimate_quantities(inputs)
  @cost.evaluate_rate_schedule(
    schedule,
    quantities.rows,
    quantities.wire_bytes,
    quantities.pairs,
  ).map_err(issue => DuckDBEstimateIssue::Rate(issue))
}
