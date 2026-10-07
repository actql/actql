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
  mut pending_choice : @strategy.StrategyChoiceSet?
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
  guard @strategy.captured_execution_root_statistics(run) is Some(root) else {
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
    pending_choice: None,
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
  // An external policy decision is outstanding. A routine refresh must not
  // replace it with the offline default while its response is in flight.
  if policy.pending_choice is Some(_) {
    return Ok(())
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
  let result = match rebuild_adaptive_dispatch(policy) {
    Err(issue) => Err(issue)
    Ok(choices) =>
      match @strategy.commit_strategy_choice(choices, None) {
        Ok(Selected(_)) => Ok(())
        Ok(_) => Err(NoStrategy)
        Err(issue) => Err(Search(issue))
      }
  }
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
/// Construct a bounded candidate set for a policy service at a planning
/// boundary. The Host may perform I/O while this owner-bound set is pending;
/// no task can dispatch until an explicit choice is committed.
pub fn[E] prepare_adaptive_policy_choice(
  policy : AdaptiveDispatch[E],
) -> Result[@strategy.StrategyChoiceSet?, AdaptiveEstimateIssue[E]] {
  if policy.failure is Some(issue) {
    return Err(issue)
  }
  if policy.pending_choice is Some(choices) {
    return Ok(Some(choices))
  }
  let run = policy.driver.owner.run
  guard @strategy.next_captured_task(run) is Some(next) else { return Ok(None) }
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  let key = (
    next,
    @strategy.captured_dag_generation(run),
    { ..usage, planning_work: 0, },
  )
  if policy.seen == Some(key) {
    return Ok(None)
  }
  match rebuild_adaptive_dispatch(policy) {
    Ok(choices) => {
      policy.seen = Some(key)
      policy.pending_choice = Some(choices)
      Ok(Some(choices))
    }
    Err(issue) => {
      policy.seen = Some(key)
      policy.failure = Some(issue)
      stop_dispatch_driver(policy.driver)
      Err(issue)
    }
  }
}

///|
/// Accept only a current feasible candidate from the pending set. `None` is
/// an explicit decision to use the offline default after a policy failure.
pub fn[E] commit_adaptive_policy_choice(
  policy : AdaptiveDispatch[E],
  position : Int?,
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  commit_adaptive_choice(policy, position)
}

///|
pub fn[E] prepare_adaptive_policy_request(
  policy : AdaptiveDispatch[E],
  request_id : String,
  run_identity : String,
  authority : String,
  deadline_ms : Int64,
  now_ms : Int64,
) -> Result[@strategy.PolicyRequest, AdaptiveEstimateIssue[E]] {
  guard policy.pending_choice is Some(choices) else {
    return Err(InvalidConfiguration)
  }
  @strategy.prepare_strategy_policy_request(
    choices, request_id, run_identity, authority, deadline_ms, now_ms,
  ).map_err(issue => Search(issue))
}

///|
pub fn[E] adaptive_policy_candidates(
  policy : AdaptiveDispatch[E],
) -> @strategy.PolicyCandidateSet? {
  policy.pending_choice.bind(choices => {
    @strategy.strategy_policy_candidates(choices)
  })
}

///|
/// Exact search counts for the currently pending choice. These counts describe
/// planner metadata, not process memory or an allocator peak.
pub fn[E] adaptive_policy_search_diagnostics(
  policy : AdaptiveDispatch[E],
) -> @strategy.StrategySearchDiagnostics? {
  policy.pending_choice.bind(choices => {
    Some(@strategy.strategy_search_diagnostics(choices))
  })
}

///|
pub fn[E] commit_adaptive_policy_decision(
  policy : AdaptiveDispatch[E],
  request : @strategy.PolicyRequest,
  response : @strategy.PolicyResponse,
  now_ms : Int64,
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  if policy.failure is Some(issue) {
    return Err(issue)
  }
  guard policy.pending_choice is Some(choices) else {
    return Err(InvalidConfiguration)
  }
  finish_adaptive_policy_choice(
    policy,
    @strategy.commit_strategy_policy_decision(
      choices, request, response, now_ms,
    ),
  )
}

///|
/// The Host must authenticate the response peer before supplying its policy
/// identity. A decoded proposal still passes the exact pending-choice commit.
pub fn[E] commit_adaptive_policy_response_json(
  policy : AdaptiveDispatch[E],
  request : @strategy.PolicyRequest,
  body : String,
  authenticated_policy_id : String,
  now_ms : Int64,
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  let response = match
    @strategy.admit_placement_policy_response_json(
      body, request, authenticated_policy_id,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Search(issue))
  }
  commit_adaptive_policy_decision(policy, request, response, now_ms)
}

///|
fn[E] commit_adaptive_choice(
  policy : AdaptiveDispatch[E],
  position : Int?,
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  if policy.failure is Some(issue) {
    return Err(issue)
  }
  guard policy.pending_choice is Some(choices) else {
    return Err(InvalidConfiguration)
  }
  finish_adaptive_policy_choice(
    policy,
    @strategy.commit_strategy_choice(choices, position),
  )
}

///|
fn[E] finish_adaptive_policy_choice(
  policy : AdaptiveDispatch[E],
  decision : Result[@strategy.StrategyDecision, @strategy.SearchIssue],
) -> Result[Unit, AdaptiveEstimateIssue[E]] {
  match decision {
    Ok(Selected(_)) => {
      policy.pending_choice = None
      Ok(())
    }
    Ok(_) => {
      policy.pending_choice = None
      policy.failure = Some(NoStrategy)
      stop_dispatch_driver(policy.driver)
      Err(NoStrategy)
    }
    Err(InvalidPreference) => Err(Search(InvalidPreference))
    Err(issue) => {
      policy.pending_choice = None
      policy.failure = Some(Search(issue))
      stop_dispatch_driver(policy.driver)
      Err(Search(issue))
    }
  }
}

///|
fn[E] rebuild_adaptive_dispatch(
  policy : AdaptiveDispatch[E],
) -> Result[@strategy.StrategyChoiceSet, AdaptiveEstimateIssue[E]] {
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
    let join = @strategy.captured_task_join_output_count(run, task).unwrap() > 0
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
  match
    @strategy.prepare_bounded_strategy_choices(run, offers, policy.registry) {
    Ok(choices) => Ok(choices)
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
