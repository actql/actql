///|
/// Explicit Host estimates, never physical reservations or admission evidence.
/// A missing coefficient remains unknown. A known zero has no quantity dependency.
pub(all) struct DispatchRate {
  work_slots : Array[Int]
  fixed_ms : Int64?
  per_row_ms : Int64?
  per_wire_byte_ms : Int64?
}

///|
pub(all) struct DispatchEstimateProfile {
  local_rates : Array[DispatchRate]
  native_rates : Array[DispatchRate]
  native_capacity : @strategy.PhysicalEnvelope
  output_rows_per_mille : Int?
}

///|
priv struct DispatchEstimates {
  root : @planning.CapturedSourceStatistics
  profiles : Array[DispatchEstimateProfile]
  limits : @strategy.SearchLimits
  estimate_work : Int
  mut seen : (Int, @strategy.LedgerUsage)?
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
    host.pending is Some(_) ||
    profiles.length() != host.generated.length() ||
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
  match @strategy.charge_planning(ledger, profiles.length()) {
    Err(issue) => return Err(Run(Physical(issue)))
    Ok(_) => ()
  }
  work -= profiles.length()
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
    for (slots, rates) in [(5, profile.local_rates), (8, profile.native_rates)] {
      if slots > work || rates.length() > work - slots {
        return Err(InvalidConfiguration)
      }
      match @strategy.charge_planning(ledger, slots + rates.length()) {
        Err(issue) => return Err(Run(Physical(issue)))
        Ok(_) => ()
      }
      work -= slots + rates.length()
      for rate in rates {
        if rate.work_slots.length() > work {
          return Err(InvalidConfiguration)
        }
        match @strategy.charge_planning(ledger, rate.work_slots.length()) {
          Err(issue) => return Err(Run(Physical(issue)))
          Ok(_) => ()
        }
        work -= rate.work_slots.length()
        for
          coefficient in [rate.fixed_ms, rate.per_row_ms, rate.per_wire_byte_ms] {
          if coefficient is Some(value) && value < 0L {
            return Err(InvalidConfiguration)
          }
        }
      }
      match
        @cost.assess_serial(
          slots,
          rates.map(rate => { work_slots: rate.work_slots, milliseconds: None, }),
          limits.max_work,
        ) {
        Err(issue) => return Err(Search(Cost(issue)))
        Ok(_) => ()
      }
    }
  }
  match @strategy.configure_strategy_search(host.run, limits) {
    Err(issue) => return Err(Search(issue))
    Ok(_) => ()
  }
  host.estimates = Some({
    root,
    limits,
    estimate_work: limits.max_work - work,
    seen: None,
    failure: None,
    profiles: profiles.map(profile => {
      ..profile,
      local_rates: profile.local_rates.map(rate => {
        ..rate,
        work_slots: rate.work_slots.copy(),
      }),
      native_rates: profile.native_rates.map(rate => {
        ..rate,
        work_slots: rate.work_slots.copy(),
      }),
    }),
  })
  Ok(())
}

///|
fn dispatch_rate_value(
  rate : DispatchRate,
  rows : Int64?,
  bytes : Int64?,
) -> Result[Int64?, DispatchIssue] {
  guard rate.fixed_ms is Some(base) &&
    rate.per_row_ms is Some(per_row) &&
    rate.per_wire_byte_ms is Some(per_byte) else {
    return Ok(None)
  }
  let mut total = base
  for (coefficient, quantity) in [(per_row, rows), (per_byte, bytes)] {
    if coefficient == 0L {
      continue
    }
    guard quantity is Some(quantity) else { return Ok(None) }
    if quantity > (9223372036854775807L - total) / coefficient {
      return Err(EstimateOverflow)
    }
    total += quantity * coefficient
  }
  Ok(Some(total))
}

///|
fn dispatch_estimate_lines(
  rates : Array[DispatchRate],
  rows : Int64?,
  bytes : Int64?,
) -> Result[Array[@cost.SerialEstimateLine], DispatchIssue] {
  let lines : Array[@cost.SerialEstimateLine] = []
  for rate in rates {
    match dispatch_rate_value(rate, rows, bytes) {
      Err(issue) => return Err(issue)
      Ok(milliseconds) =>
        lines.push({ work_slots: rate.work_slots, milliseconds, })
    }
  }
  Ok(lines)
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
  let usage = @strategy.ledger_usage(@strategy.captured_dag_ledger(host.run))
  let key = (next, { ..usage, planning_work: 0, })
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
    @strategy.charge_planning(@strategy.captured_dag_ledger(run), count + edges) {
    Err(issue) => return Err(Run(Physical(issue)))
    Ok(_) => ()
  }
  match
    @strategy.charge_planning(
      @strategy.captured_dag_ledger(run),
      policy.estimate_work,
    ) {
    Err(issue) => return Err(Run(Physical(issue)))
    Ok(_) => ()
  }
  let parents = Array::make(count, 0)
  for i in 0..<edges {
    let edge = @strategy.graph_data_at(graph, i).unwrap()
    parents[edge.consumer] = edge.producer
  }
  let rows : Array[Int64?] = Array::make(count, None)
  rows[0] = Some(policy.root.rows.to_int64())
  let offers = []
  for task in 1..<count {
    let profile = policy.profiles[task - 1]
    let input_rows = rows[parents[task]]
    // Only the root's retained wire count is observed. Future output sizes are
    // deliberately unknown; no fresh scan or invented compression ratio.
    let input_bytes = if parents[task] == 0 {
      Some(policy.root.canonical_wire_bytes.to_int64())
    } else {
      None
    }
    rows[task] = match (input_rows, profile.output_rows_per_mille) {
      (Some(value), Some(fraction)) => {
        let f = fraction.to_int64()
        Some(value / 1000L * f + (value % 1000L * f + 999L) / 1000L)
      }
      _ => None
    }
    if @strategy.captured_task_output(run, task, Step(1)) is Some(output) {
      rows[task] = Some(@execution.completed_row_count(output).to_int64())
    }
    if @strategy.captured_task_completed(run, task) {
      continue
    }
    guard @execution.generated_sequence_capacity(
        host.generated[task - 1],
        host.limits.local_execution,
        host.limits.guards,
      )
      is Some(local_capacity) else {
      return Err(InvalidConfiguration)
    }
    let local_envelope : @strategy.PhysicalEnvelope = {
      transfer_bytes: 0L,
      retained_bytes: local_capacity.retained_bytes,
      execution_bytes: local_capacity.execution_bytes,
    }
    for
      (slots, rates, registration, capacity) in [
        (5, profile.local_rates, host.local_registration, local_envelope),
        (
          8,
          profile.native_rates,
          host.native_registration,
          profile.native_capacity,
        ),
      ] {
      let lines = match
        dispatch_estimate_lines(rates, input_rows, input_bytes) {
        Ok(lines) => lines
        Err(issue) => return Err(issue)
      }
      match
        @strategy.prepare_task_offer(
          run,
          task,
          registration,
          slots,
          lines,
          capacity,
          policy.limits.max_work,
        ) {
        Ok(offer) => offers.push(offer)
        Err(issue) => return Err(Search(issue))
      }
    }
  }
  match @strategy.revise_strategy(run, offers, host.registry, None) {
    Ok(Selected(_)) => Ok(())
    Ok(_) => Err(NoStrategy)
    Err(issue) => Err(Search(issue))
  }
}
