///|
pub(all) struct LocalEstimateSettings {
  schedules : Array[@cost.RateSchedule]
  max_work : Int
}

///|
pub fn prepare_local_estimate_settings(
  installed : LocalDispatchModule,
  settings : LocalEstimateSettings,
) -> Result[LocalEstimateModule, LocalEstimateIssue] {
  prepare_local_estimate_module(
    installed,
    settings.schedules,
    settings.max_work,
  )
}

///|
struct LocalEstimateModule {
  installed : LocalDispatchModule
  configuration : LocalEstimateConfiguration
}

///|
priv struct LocalEstimateConfiguration {
  schedules : Array[@cost.RateSchedule]
  max_work : Int
}

///|
pub(all) enum LocalEstimateIssue {
  InvalidConfiguration
  Rate(@cost.RateIssue)
  Dispatch(LocalDispatchIssue)
}

///|
pub fn prepare_local_estimate_module(
  installed : LocalDispatchModule,
  schedules : Array[@cost.RateSchedule],
  max_work : Int,
) -> Result[LocalEstimateModule, LocalEstimateIssue] {
  if max_work < 0 ||
    schedules.length() > max_work ||
    schedules.length() !=
    @strategy.graph_task_count(@strategy.captured_dag_graph(installed.run)) - 1 {
    return Err(InvalidConfiguration)
  }
  Ok({ installed, configuration: { schedules: schedules.copy(), max_work, }, })
}

///|
pub fn estimate_local_module_offers(
  policy : LocalEstimateModule,
  task : Int,
  quantities : @host.TaskEstimateQuantities,
) -> Result[Array[@strategy.TaskOffer], LocalEstimateIssue] {
  estimate_local_configuration(
    policy.installed,
    policy.configuration,
    task,
    quantities,
  )
}

///|
fn estimate_local_configuration(
  installed : LocalDispatchModule,
  configuration : LocalEstimateConfiguration,
  task : Int,
  quantities : @host.TaskEstimateQuantities,
) -> Result[Array[@strategy.TaskOffer], LocalEstimateIssue] {
  guard task > 0 && configuration.schedules.get(task - 1) is Some(schedule) else {
    return Err(InvalidConfiguration)
  }
  if local_dispatch_rejection(installed, task) is Some(_) {
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
  estimate_local_dispatch_offer(installed, task, lines, configuration.max_work)
  .map(offer => [offer])
  .map_err(issue => Dispatch(issue))
}

///|
pub fn install_local_dispatch_estimates(
  installed : LocalDispatchModule,
  policy : LocalEstimateModule,
) -> Result[Unit, LocalEstimateIssue] {
  if installed.estimate_configuration is Some(_) ||
    !physical_equal(installed, policy.installed) ||
    @strategy.strategy_history_count(installed.run) != 0 {
    return Err(InvalidConfiguration)
  }
  installed.estimate_configuration = Some(policy.configuration)
  Ok(())
}

///|
pub fn estimate_local_installed_offers(
  installed : LocalDispatchModule,
  task : Int,
  quantities : @host.TaskEstimateQuantities,
) -> Result[Array[@strategy.TaskOffer], LocalEstimateIssue] {
  guard installed.estimate_configuration is Some(configuration) else {
    return Err(InvalidConfiguration)
  }
  estimate_local_configuration(installed, configuration, task, quantities)
}
