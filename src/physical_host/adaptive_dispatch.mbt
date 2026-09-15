///|
/// Connector-free adaptive planning over an immutable implementation installation.
/// Statistics affect estimates only; the driver retains dispatch and input checks.
struct AdaptiveDispatch[E] {
  driver : DispatchDriver
  registry : @connector.CapabilityRegistry
  root_rows : Int64
  root_bytes : Int64
  output_rows_per_mille : Array[Int?]
  limits : @strategy.SearchLimits
  estimate_work : Int
  implementations : @connector.CapabilityImplementations[
    (Unit, Int, TaskEstimateQuantities) -> Result[Array[@strategy.TaskOffer], E],
  ]
  mut seen : (Int, Int, @resources.LedgerUsage)?
  mut failure : AdaptiveEstimateIssue[E]?
}

///|
pub(all) enum AdaptiveEstimateIssue[E] {
  InvalidConfiguration
  NoStrategy
  ForeignSelection
  EstimateOverflow
  Resources(@resources.LedgerIssue)
  Search(@strategy.SearchIssue)
  Implementation(E)
}

///|
pub fn[E] open_adaptive_dispatch(
  driver : DispatchDriver,
  registry : @connector.CapabilityRegistry,
  implementations : @connector.CapabilityImplementations[
    (Unit, Int, TaskEstimateQuantities) -> Result[Array[@strategy.TaskOffer], E],
  ],
  output_rows_per_mille : Array[Int?],
  limits : @strategy.SearchLimits,
  estimate_work : Int,
) -> Result[AdaptiveDispatch[E], AdaptiveEstimateIssue[E]] {
  let run = driver.owner.run
  if dispatch_driver_pending(driver) ||
    limits.max_work < 0 ||
    limits.max_offers < 0 ||
    limits.max_strategies < 1 ||
    limits.max_revisions < 1 ||
    estimate_work < 0 ||
    estimate_work > limits.max_work ||
    output_rows_per_mille.length() > limits.max_work ||
    output_rows_per_mille.length() !=
    @strategy.graph_task_count(@strategy.captured_dag_graph(run)) - 1 {
    return Err(InvalidConfiguration)
  }
  guard @strategy.captured_root_statistics(run) is Some(root) else {
    return Err(InvalidConfiguration)
  }
  let registration_limit = if limits.max_offers <
    limits.max_work - output_rows_per_mille.length() {
    limits.max_offers
  } else {
    limits.max_work - output_rows_per_mille.length()
  }
  guard @connector.capability_implementation_registrations(
      implementations, registration_limit,
    )
    is Some(registrations) else {
    return Err(InvalidConfiguration)
  }
  match
    @resources.charge_planning(
      @strategy.captured_dag_ledger(run),
      output_rows_per_mille.length() + registrations.length(),
    ) {
    Err(issue) => return Err(Resources(issue))
    Ok(_) => ()
  }
  for registration in registrations {
    if !@connector.capability_registration_matches(registration, registry) ||
      !@connector.capability_registration_available(registration) {
      return Err(ForeignSelection)
    }
  }
  for fraction in output_rows_per_mille {
    if fraction is Some(value) && (value < 0 || value > 1000) {
      return Err(InvalidConfiguration)
    }
  }
  match @strategy.configure_strategy_search(run, limits) {
    Err(issue) => return Err(Search(issue))
    Ok(_) => ()
  }
  Ok({
    driver,
    registry,
    implementations,
    root_rows: root.rows.to_int64(),
    root_bytes: root.canonical_wire_bytes.to_int64(),
    output_rows_per_mille: output_rows_per_mille.copy(),
    limits,
    estimate_work,
    seen: None,
    failure: None,
  })
}

///|
/// A failed refresh stays failed: retrying preparation cannot silently dispatch
/// the previously selected strategy or spend planning work again in a loop.
pub fn[E] refresh_adaptive_dispatch(
  policy : AdaptiveDispatch[E],
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  let run = policy.driver.owner.run
  if policy.failure is Some(issue) {
    return Err(issue)
  }
  guard @strategy.next_captured_task(run) is Some(next) else { return Ok(()) }
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  let key = (
    next,
    @strategy.captured_dag_generation(run),
    { ..usage, planning_work: 0, },
  )
  if policy.seen == Some(key) {
    return Ok(())
  }
  let result = rebuild_adaptive_dispatch(policy)
  policy.seen = Some(key)
  if result is Err(issue) {
    policy.failure = Some(issue)
    // Failure cannot be bypassed by starting a ticket prepared outside this
    // policy. Existing completions and cleanup obligations remain owned.
    stop_dispatch_driver(policy.driver)
  }
  result
}

///|
fn[E] rebuild_adaptive_dispatch(
  policy : AdaptiveDispatch[E],
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  let run = policy.driver.owner.run
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
    Err(issue) => return Err(Resources(issue))
    Ok(_) => ()
  }
  match
    @resources.charge_planning(
      @strategy.captured_dag_ledger(run),
      policy.estimate_work,
    ) {
    Err(issue) => return Err(Resources(issue))
    Ok(_) => ()
  }
  let parents : Array[Array[Int]] = Array::makei(count, _ => [])
  for i in 0..<edges {
    let edge = @strategy.graph_data_at(graph, i).unwrap()
    parents[edge.consumer].push(edge.producer)
  }
  let rows : Array[Int64?] = Array::make(count, None)
  rows[0] = Some(policy.root_rows)
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
            Some(policy.root_bytes)
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
      collect_installed_task_offers(
        policy.driver,
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
      Err(Implementation(issue)) => return Err(Implementation(issue))
      Err(OfferLimit) => return Err(Search(OfferLimit))
      Err(InvalidLimits) => return Err(InvalidConfiguration)
      Err(Unavailable) | Err(ForeignOffer) => return Err(ForeignSelection)
    }
  }
  match @strategy.revise_strategy(run, offers, policy.registry, None) {
    Ok(Selected(_)) => Ok(())
    Ok(_) => Err(NoStrategy)
    Err(issue) => Err(Search(issue))
  }
}

///|
fn[E] sum_dispatch_quantities(
  values : Array[Int64?],
) -> Result[Int64?, AdaptiveEstimateIssue[E]] {
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
fn[E] dispatch_pair_quantity(
  left : Int64?,
  right : Int64?,
) -> Result[Int64?, AdaptiveEstimateIssue[E]] {
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
