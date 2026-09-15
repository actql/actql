///|
/// Standard composition entry for the installed Local realization.
fn estimate_local_task_offers(
  context : (StrategyHostDispatch, DispatchEstimates),
  task : Int,
  quantities : @host_driver.TaskEstimateQuantities,
) -> Result[Array[@strategy.TaskOffer], DispatchIssue] {
  let (host, policy) = context
  let profile = policy.profiles[task - 1]
  let lines = match
    dispatch_estimate_lines(
      profile.local_rates,
      quantities.rows,
      quantities.wire_bytes,
      quantities.pairs,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @local_driver.estimate_local_dispatch_offer(
    host.local_module,
    task,
    lines,
    policy.limits.max_work,
  )
  .map(offer => [offer])
  .map_err(local_dispatch_issue)
}

///|
/// Fresh and reusable representations are alternatives from one implementation.
/// Their occurrence ordering is retained for stable strategy positions.
fn estimate_duckdb_task_offers(
  context : (StrategyHostDispatch, DispatchEstimates),
  task : Int,
  quantities : @host_driver.TaskEstimateQuantities,
) -> Result[Array[@strategy.TaskOffer], DispatchIssue] {
  let (host, policy) = context
  if host.native_rejections[task - 1] is Some(_) {
    return Ok([])
  }
  let profile = policy.profiles[task - 1]
  let lines = match
    dispatch_estimate_lines(
      profile.native_rates,
      quantities.rows,
      quantities.wire_bytes,
      quantities.pairs,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let base = match
    @duckdb_driver.estimate_duckdb_task_offer(
      host.run,
      task,
      host.native_registration,
      lines,
      profile.native_capacity,
      policy.limits.max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Search(issue))
  }
  let offers = [base]
  if host.resident is Some(resident) &&
    host.resident_rejections[task - 1] is None {
    let lines = match
      dispatch_estimate_lines(
        resident.rates[task - 1],
        quantities.rows,
        quantities.wire_bytes,
        quantities.pairs,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match
      @duckdb_driver.estimate_duckdb_task_offer(
        host.run,
        task,
        host.native_registration,
        lines,
        profile.native_capacity,
        policy.limits.max_work,
        resident=resident.profile,
      ) {
      Ok(value) => offers.push(value)
      Err(issue) => return Err(Search(issue))
    }
  }
  Ok(offers)
}
