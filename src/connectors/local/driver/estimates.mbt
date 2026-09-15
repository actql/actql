///|
struct LocalEstimateModule {
  installed : LocalDispatchModule
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
  Ok({ installed, schedules: schedules.copy(), max_work, })
}

///|
pub fn estimate_local_module_offers(
  policy : LocalEstimateModule,
  task : Int,
  quantities : @host.TaskEstimateQuantities,
) -> Result[Array[@strategy.TaskOffer], LocalEstimateIssue] {
  guard task > 0 && policy.schedules.get(task - 1) is Some(schedule) else {
    return Err(InvalidConfiguration)
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
  estimate_local_dispatch_offer(policy.installed, task, lines, policy.max_work)
  .map(offer => [offer])
  .map_err(issue => Dispatch(issue))
}
