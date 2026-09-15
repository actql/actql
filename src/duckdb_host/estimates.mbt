///|
pub(all) struct DispatchEstimateProfile {
  local_rates : Array[@cost.WorkRate]
  native_rates : Array[@cost.WorkRate]
  native_capacity : @strategy.PhysicalEnvelope
  output_rows_per_mille : Int?
}

///|
/// Install before the first search. Unknown totals defer; no implicit Host
/// preference, measured-speed claim, or fallback is introduced by this policy.
pub fn configure_dispatch_estimates(
  host : StrategyHostDispatch,
  profiles : Array[DispatchEstimateProfile],
  limits : @strategy.SearchLimits,
) -> Result[Unit, DispatchIssue] {
  if host.estimates is Some(_) ||
    @host_driver.dispatch_driver_pending(host.driver) ||
    profiles.length() !=
    @strategy.graph_task_count(@strategy.captured_dag_graph(host.run)) - 1 ||
    limits.max_work < 0 ||
    profiles.length() > limits.max_offers / 2 ||
    limits.max_offers < 0 ||
    limits.max_strategies < 1 ||
    limits.max_revisions < 1 {
    return Err(InvalidConfiguration)
  }
  let mut work = limits.max_work
  if profiles.length() > work {
    return Err(InvalidConfiguration)
  }
  let ledger = @strategy.captured_dag_ledger(host.run)
  work -= profiles.length()
  let local_schedules = []
  let native_schedules = []
  let capacities = []
  for profile in profiles {
    if profile.output_rows_per_mille is Some(value) &&
      (value < 0 || value > 1000) {
      return Err(InvalidConfiguration)
    }
    let cap = profile.native_capacity
    if cap.transfer_bytes < 0L ||
      cap.retained_bytes < 0L ||
      cap.execution_bytes < 0L {
      return Err(InvalidConfiguration)
    }
    let schedules = []
    for
      (slots, rates) in [
        (@local_driver.local_dispatch_work_slots(), profile.local_rates),
        (@duckdb_driver.duckdb_dispatch_work_slots(), profile.native_rates),
      ] {
      if slots > work || rates.length() > work - slots {
        return Err(InvalidConfiguration)
      }
      match @resources.charge_planning(ledger, slots + rates.length()) {
        Err(issue) => return Err(Run(Physical(issue)))
        Ok(_) => ()
      }
      work -= slots + rates.length()
      for rate in rates {
        if rate.work_slots.length() > work {
          return Err(InvalidConfiguration)
        }
        match @resources.charge_planning(ledger, rate.work_slots.length()) {
          Err(issue) => return Err(Run(Physical(issue)))
          Ok(_) => ()
        }
        work -= rate.work_slots.length()
        for
          coefficient in [
            rate.fixed_ms,
            rate.per_row_ms,
            rate.per_wire_byte_ms,
            rate.per_pair_ms,
          ] {
          if coefficient is Some(value) && value < 0L {
            return Err(InvalidConfiguration)
          }
        }
      }
      match @cost.prepare_rate_schedule(slots, rates, limits.max_work) {
        Err(issue) => return Err(dispatch_rate_issue(issue))
        Ok(schedule) => schedules.push(schedule)
      }
    }
    local_schedules.push(schedules[0])
    native_schedules.push(schedules[1])
    capacities.push(profile.native_capacity)
  }
  let local_policy = match
    @local_driver.prepare_local_estimate_module(
      host.local_module,
      local_schedules,
      limits.max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(local_estimate_issue(issue))
  }
  let native_policy = match
    @duckdb_driver.prepare_duckdb_estimate_module(
      host.native_module,
      native_schedules,
      capacities,
      limits.max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(duckdb_estimate_issue(issue))
  }
  let implementations = match
    @connector.install_capability_implementations(
      host.registry,
      [
        (
          host.local_registration,
          fn(_context, task, quantities) {
            @local_driver.estimate_local_module_offers(
              local_policy, task, quantities,
            ).map_err(local_estimate_issue)
          },
        ),
        (
          host.native_registration,
          fn(_context, task, quantities) {
            @duckdb_driver.estimate_duckdb_module_offers(
              native_policy, task, quantities,
            ).map_err(duckdb_estimate_issue)
          },
        ),
      ],
      2,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidConfiguration)
  }
  let policy = match
    @host_driver.open_adaptive_dispatch(
      host.driver,
      host.registry,
      implementations,
      profiles.map(profile => profile.output_rows_per_mille),
      limits,
      limits.max_work - work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(adaptive_estimate_issue(issue))
  }
  host.estimates = Some(policy)
  Ok(())
}

///|
fn dispatch_rate_issue(issue : @cost.RateIssue) -> DispatchIssue {
  match issue {
    Overflow => EstimateOverflow
    Coverage(issue) => Search(Cost(issue))
    InvalidQuantity | InvalidCoefficient => InvalidConfiguration
  }
}

///|
fn adaptive_estimate_issue(
  issue : @host_driver.AdaptiveEstimateIssue[DispatchIssue],
) -> DispatchIssue {
  match issue {
    InvalidConfiguration => InvalidConfiguration
    NoStrategy => NoStrategy
    ForeignSelection => ForeignSelection
    EstimateOverflow => EstimateOverflow
    Resources(issue) => Run(Physical(issue))
    Search(issue) => Search(issue)
    Implementation(issue) => issue
  }
}

///|
pub fn refresh_dispatch_estimates(
  host : StrategyHostDispatch,
) -> Result[Unit, DispatchIssue] {
  guard host.estimates is Some(policy) else { return Ok(()) }
  @host_driver.refresh_adaptive_dispatch(policy).map_err(
    adaptive_estimate_issue,
  )
}
