///|
pub(all) struct LocalEstimateSettings {
  schedules : Array[@cost.RateSchedule]
  eligible : Array[Bool]
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
    eligible=settings.eligible,
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
  eligible : Array[Bool]
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
  eligible? : Array[Bool] = [],
) -> Result[LocalEstimateModule, LocalEstimateIssue] {
  if max_work < 0 ||
    schedules.length() > max_work ||
    (!eligible.is_empty() && eligible.length() != schedules.length()) ||
    schedules.length() !=
    @strategy.graph_task_count(@strategy.captured_dag_graph(installed.run)) -
    @strategy.captured_compute_first_task(installed.run) {
    return Err(InvalidConfiguration)
  }
  installed.policy_sealed = true
  Ok({
    installed,
    configuration: {
      schedules: schedules.copy(),
      eligible: eligible.copy(),
      max_work,
    },
  })
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
  guard task >= @strategy.captured_compute_first_task(installed.run) &&
    configuration.schedules.get(local_task_slot(installed, task))
    is Some(schedule) else {
    return Err(InvalidConfiguration)
  }
  if configuration.eligible.get(task - 1) is Some(false) {
    return Ok([])
  }
  if local_dispatch_rejection(installed, task) is Some(_) &&
    !@local.local_module_managed_sequence_supported(
      installed.implementation,
      local_task_slot(installed, task),
    ) {
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

///|
/// Reuse the Host-installed Local rate schedule for managed candidate
/// comparison. Missing policy or quantities stay unknown. This function is
/// pure: completed producer metadata is inspected without acquiring a
/// representation use right or reserving execution resources.
fn local_managed_estimate_lines(
  installed : LocalDispatchModule,
  task : Int,
  row_counts : Array[Int],
) -> Result[Array[@cost.SerialEstimateLine], LocalEstimateIssue] {
  guard task >= @strategy.captured_compute_first_task(installed.run) else {
    return Err(InvalidConfiguration)
  }
  guard installed.estimate_configuration is Some(configuration) else {
    return Ok([
      {
        work_slots: Array::makei(local_dispatch_work_slots(), index => index),
        milliseconds: None,
      },
    ])
  }
  guard configuration.schedules.get(local_task_slot(installed, task))
    is Some(schedule) else {
    return Err(InvalidConfiguration)
  }
  if configuration.eligible.get(task - 1) is Some(false) {
    return Err(InvalidConfiguration)
  }
  let mut rows = 0L
  let mut rows_known = true
  for count in row_counts {
    let value = count.to_int64()
    if value < 0L || value > 9223372036854775807L - rows {
      rows_known = false
    } else if rows_known {
      rows += value
    }
  }
  let pairs = if row_counts.length() == 2 {
    let left = row_counts[0].to_int64()
    let right = row_counts[1].to_int64()
    if left < 0L ||
      right < 0L ||
      (right > 0L && left > 9223372036854775807L / right) {
      None
    } else {
      Some(left * right)
    }
  } else {
    Some(0L)
  }
  @cost.evaluate_rate_schedule(
    schedule,
    if rows_known {
      Some(rows)
    } else {
      None
    },
    None,
    pairs,
  ).map_err(issue => LocalEstimateIssue::Rate(issue))
}
