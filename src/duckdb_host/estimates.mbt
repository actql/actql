///|
pub(all) struct DispatchEstimateProfile {
  local_rates : Array[@cost.WorkRate]
  native_rates : Array[@cost.WorkRate]
  native_capacity : @strategy.PhysicalEnvelope
  output_rows_per_mille : Int?
}

///|
priv struct DispatchEstimates {
  root : @query.CapturedSourceStatistics
  output_rows_per_mille : Array[Int?]
  limits : @strategy.SearchLimits
  estimate_work : Int
  implementations : @connector.CapabilityImplementations[
    (Unit, Int, @host_driver.TaskEstimateQuantities) -> Result[
      Array[@strategy.TaskOffer],
      DispatchIssue,
    ],
  ]
  mut seen : (Int, Int, @resources.LedgerUsage)?
  mut failure : DispatchIssue?
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
  guard @strategy.captured_root_statistics(host.run) is Some(root) else {
    return Err(InvalidConfiguration)
  }
  let mut work = limits.max_work
  if profiles.length() > work {
    return Err(InvalidConfiguration)
  }
  let ledger = @strategy.captured_dag_ledger(host.run)
  match @resources.charge_planning(ledger, profiles.length()) {
    Err(issue) => return Err(Run(Physical(issue)))
    Ok(_) => ()
  }
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
  match @strategy.configure_strategy_search(host.run, limits) {
    Err(issue) => return Err(Search(issue))
    Ok(_) => ()
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
  host.estimates = Some({
    implementations,
    root,
    limits,
    estimate_work: limits.max_work - work,
    seen: None,
    failure: None,
    output_rows_per_mille: profiles.map(profile => profile.output_rows_per_mille),
  })
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
/// A failed refresh stays failed: retrying preparation cannot silently dispatch
/// the previously selected strategy or spend planning work again in a loop.
pub fn refresh_dispatch_estimates(
  host : StrategyHostDispatch,
) -> Result[Unit, DispatchIssue] {
  guard host.estimates is Some(policy) else { return Ok(()) }
  if policy.failure is Some(issue) {
    return Err(issue)
  }
  guard @strategy.next_captured_task(host.run) is Some(next) else {
    return Ok(())
  }
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(host.run))
  let key = (
    next,
    @strategy.captured_dag_generation(host.run),
    { ..usage, planning_work: 0, },
  )
  if policy.seen == Some(key) {
    return Ok(())
  }
  let result = rebuild_dispatch_estimates(host, policy)
  policy.seen = Some(key)
  if result is Err(issue) {
    policy.failure = Some(issue)
  }
  result
}

///|
fn rebuild_dispatch_estimates(
  host : StrategyHostDispatch,
  policy : DispatchEstimates,
) -> Result[Unit, DispatchIssue] {
  let run = host.run
  let graph = @strategy.captured_dag_graph(run)
  let count = @strategy.graph_task_count(graph)
  let edges = @strategy.graph_data_count(graph)
  if count > policy.limits.max_work || edges > policy.limits.max_work - count {
    return Err(InvalidConfiguration)
  }
  match
    @resources.charge_planning(
      @strategy.captured_dag_ledger(run),
      count + edges,
    ) {
    Err(issue) => return Err(Run(Physical(issue)))
    Ok(_) => ()
  }
  match
    @resources.charge_planning(
      @strategy.captured_dag_ledger(run),
      policy.estimate_work,
    ) {
    Err(issue) => return Err(Run(Physical(issue)))
    Ok(_) => ()
  }
  let parents : Array[Array[Int]] = Array::makei(count, _ => [])
  for i in 0..<edges {
    let edge = @strategy.graph_data_at(graph, i).unwrap()
    parents[edge.consumer].push(edge.producer)
  }
  let rows : Array[Int64?] = Array::make(count, None)
  rows[0] = Some(policy.root.rows.to_int64())
  let offers = []
  for task in 1..<count {
    let output_fraction = policy.output_rows_per_mille[task - 1]
    let input_rows = match
      sum_dispatch_quantities(parents[task].map(parent => rows[parent])) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    // Only the root's retained wire count is observed. Future output sizes are
    // deliberately unknown; no fresh scan or invented compression ratio.
    let input_bytes = match
      sum_dispatch_quantities(
        parents[task].map(parent => {
          if parent == 0 {
            Some(policy.root.canonical_wire_bytes.to_int64())
          } else {
            None
          }
        }),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let join = @strategy.captured_task_join_output_limit(run, task) is Some(_)
    let pairs = if join {
      let left = rows[parents[task][0]]
      let right = rows[parents[task][parents[task].length() - 1]]
      match dispatch_pair_quantity(left, right) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    } else {
      Some(0L)
    }
    rows[task] = match
      (if join { pairs } else { input_rows }, output_fraction) {
      (Some(value), Some(fraction)) => {
        let f = fraction.to_int64()
        Some(value / 1000L * f + (value % 1000L * f + 999L) / 1000L)
      }
      _ => None
    }
    if @strategy.captured_task_target(run, task) is Some(target) &&
      @strategy.captured_task_output(run, task, target) is Some(output) {
      rows[task] = Some(@execution.completed_row_count(output).to_int64())
    }
    if @strategy.captured_task_completed(run, task) {
      continue
    }
    match
      @host_driver.collect_installed_task_offers(
        host.driver,
        policy.implementations,
        (),
        task,
        { rows: input_rows, wire_bytes: input_bytes, pairs, },
        policy.limits.max_offers,
        policy.limits.max_offers - offers.length(),
      ) {
      Ok(proposed) =>
        for offer in proposed {
          offers.push(offer)
        }
      Err(Implementation(issue)) => return Err(issue)
      Err(OfferLimit) => return Err(Search(OfferLimit))
      Err(InvalidLimits) => return Err(InvalidConfiguration)
      Err(Unavailable) | Err(ForeignOffer) => return Err(ForeignSelection)
    }
  }
  match @strategy.revise_strategy(run, offers, host.registry, None) {
    Ok(Selected(_)) => Ok(())
    Ok(_) => Err(NoStrategy)
    Err(issue) => Err(Search(issue))
  }
}

///|
fn sum_dispatch_quantities(
  values : Array[Int64?],
) -> Result[Int64?, DispatchIssue] {
  let mut total = 0L
  let mut unknown = false
  for value in values {
    match value {
      None => unknown = true
      Some(value) => {
        if value > 9223372036854775807L - total {
          return Err(EstimateOverflow)
        }
        total += value
      }
    }
  }
  Ok(if unknown { None } else { Some(total) })
}

///|
/// Potential pairs are an estimate basis, never an output-cardinality proof.
fn dispatch_pair_quantity(
  left : Int64?,
  right : Int64?,
) -> Result[Int64?, DispatchIssue] {
  match (left, right) {
    (Some(0L), _) | (_, Some(0L)) => Ok(Some(0L))
    (Some(left), Some(right)) => {
      if left > 9223372036854775807L / right {
        return Err(EstimateOverflow)
      }
      Ok(Some(left * right))
    }
    _ => Ok(None)
  }
}
