///|
pub(all) struct SearchLimits {
  max_offers : Int
  max_strategies : Int
  max_work : Int
  max_revisions : Int
}

///|
priv struct SearchResources {
  planning_capacity : Int
  attempt_capacity : Int
  holding_capacity : Int
  attempts : Int
  holdings : Int
  transferred : Int64
  uncertain_transfer : Int64
  transfer : Int64
  held : Int64
  retention : Int64
  execution : Int64
} derive(Eq)

///|
/// Declared enforceable capacities, not estimated usage or semantic evidence.
pub(all) struct PhysicalEnvelope {
  transfer_bytes : Int64
  retained_bytes : Int64
  execution_bytes : Int64
} derive(Eq, Debug)

///|
/// A Host's conditional future-task estimate. This does not manufacture a
/// ProducerRead or discharge runtime admission. Actual candidate binding remains
/// mandatory once this task's exact completed input becomes available.
struct TaskOffer {
  owner : StrategyOfferOwner
  task : Int
  registration : @connector.CapabilityRegistration
  duration : @cost.DurationEstimate
  capacity : PhysicalEnvelope
  work_slots : Int
  lines : Array[@cost.SerialEstimateLine]
  resident : ResidentProfile?
  resident_output_bytes : Int64
}

///|
/// Separate ownership token avoids run -> revision -> offer -> run cycles.
priv struct StrategyOfferOwner {
  graph : CheckedDAG
}

///|
pub struct StrategyAssessment {
  position : Int
  duration : @cost.DurationEstimate
  rejection : @resources.LedgerIssue?
  transfer_bytes : Int64
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
/// Exact planner-side counts. `peak_index_cells` counts live frontier path
/// entries before truncation; it is not process RSS or allocator telemetry.
pub(all) struct StrategySearchDiagnostics {
  complete : Bool
  evaluated_assignments : Int
  generated_prefixes : Int
  peak_frontier_states : Int
  peak_index_cells : Int
}

///|
struct StrategyRevision {
  number : Int
  generation : Int
  choices : Array[TaskOffer?]
  assessment : StrategyAssessment
  before : @resources.LedgerUsage
  search_complete : Bool
  estimated_fastest : Bool
  selection_source : StrategySelectionSource
}

///|
pub(all) struct PolicyDecisionRef {
  policy_id : String
  revision : String
  request_id : String
  explanation : String
} derive(Eq, Debug)

///|
/// Transport-neutral consultation identity. The Host supplies the authenticated
/// Run and authority identities; the common planner fixes the candidate set.
pub(all) struct PolicyRequest {
  version : String
  request_id : String
  run_identity : String
  authority : String
  candidate_set_cid : String
  generation : Int
  revision : Int
  deadline_ms : Int64
} derive(Eq, Debug)

///|
/// Exact bounded candidate data for a policy consultation. A Host may send
/// these canonical bytes to an external ranker; no local offer handles escape.
pub(all) struct PolicyCandidateSet {
  cid : String
  canonical_json : String
} derive(Eq, Debug)

///|
/// A policy proposes a member of the exact request, never a new capability.
pub(all) struct PolicyResponse {
  request : PolicyRequest
  position : Int
  policy_id : String
  policy_revision : String
  explanation : String
} derive(Eq, Debug)

///|
pub(all) enum StrategySelectionSource {
  OfflineLatency
  BoundedLatency
  HostProposal
  ExternalPolicy(PolicyDecisionRef)
} derive(Eq, Debug)

///|
/// A bounded, owner-bound choice set. A policy may inspect its feasible
/// candidates outside the search call and propose one existing position. The
/// proposal remains provisional until committed against the current Run.
struct StrategyChoiceSet {
  run : CapturedDAG
  registry : @connector.CapabilityRegistry
  generation : Int
  resources : SearchResources
  revision : Int
  feasible : Array[StrategyRevision]
  durations : Array[@cost.DurationEstimate]
  priority : Array[Int]?
  diagnostics : StrategySearchDiagnostics
  mut committed : Bool
  mut pending_policy_request : PolicyRequest?
  mut pending_policy_candidates : PolicyCandidateSet?
}

///|
pub(all) enum SearchIssue {
  InvalidLimits
  AlreadyConfigured
  NotConfigured
  UnchangedState
  Busy
  Stopped
  RevisionLimit
  OfferLimit
  StrategyLimit
  MissingTask(Int)
  ForeignOffer(Int)
  CapabilityUnavailable(Int)
  InvalidCapacity
  InvalidPreference
  StaleChoice
  Overflow
  Cost(@cost.CostIssue)
  Ledger(@resources.LedgerIssue)
}

///|
pub enum StrategyDecision {
  Selected(StrategyRevision)
  Deferred
  NoFeasible
}

///|
pub fn configure_strategy_search(
  run : CapturedDAG,
  limits : SearchLimits,
) -> Result[Unit, SearchIssue] {
  if run.search is Some(_) {
    return Err(AlreadyConfigured)
  }
  if run.generation != 0 || run.running is Some(_) {
    return Err(Busy)
  }
  if run.stopped {
    return Err(Stopped)
  }
  if limits.max_offers < 0 ||
    limits.max_strategies < 1 ||
    limits.max_work < 0 ||
    limits.max_revisions < 1 {
    return Err(InvalidLimits)
  }
  run.search = Some(limits)
  Ok(())
}

///|
pub fn prepare_task_offer(
  run : CapturedDAG,
  task : Int,
  registration : @connector.CapabilityRegistration,
  work_slots : Int,
  lines : Array[@cost.SerialEstimateLine],
  capacity : PhysicalEnvelope,
  max_work : Int,
) -> Result[TaskOffer, SearchIssue] {
  if task < 1 || task >= run.graph.owners.length() || task_done(run, task) {
    return Err(ForeignOffer(task))
  }
  if !@connector.capability_description(registration).fixed_compute {
    return Err(CapabilityUnavailable(task))
  }
  if capacity.transfer_bytes < 0L ||
    capacity.retained_bytes < 0L ||
    capacity.execution_bytes < 0L {
    return Err(InvalidCapacity)
  }
  if max_work < 0 || work_slots < 0 {
    return Err(InvalidLimits)
  }
  let work = { ledger: run.ledger, remaining: max_work, }
  match search_charge(work, work_slots) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match search_charge(work, lines.length()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  for line in lines {
    match search_charge(work, line.work_slots.length()) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  match @cost.assess_serial(work_slots, lines, max_work) {
    Err(issue) => Err(Cost(issue))
    Ok(duration) =>
      Ok({
        owner: run.offer_owner,
        task,
        registration,
        duration,
        capacity,
        work_slots,
        lines: lines.map(line => {
          work_slots: line.work_slots.copy(),
          milliseconds: line.milliseconds,
        }),
        resident: None,
        resident_output_bytes: 0L,
      })
  }
}

///|
priv struct SearchWork {
  ledger : @resources.Ledger
  mut remaining : Int
}

///|
/// Ownership projection for installed offer collection, not selection or start
/// authority. Equal task contents or registration descriptions are insufficient.
pub fn task_offer_matches(
  run : CapturedDAG,
  task : Int,
  registration : @connector.CapabilityRegistration,
  offer : TaskOffer,
) -> Bool {
  physical_equal(run.offer_owner, offer.owner) &&
  task == offer.task &&
  physical_equal(registration, offer.registration) &&
  @connector.capability_registration_available(registration)
}

///|
fn search_charge(work : SearchWork, amount : Int) -> Result[Unit, SearchIssue] {
  if amount > work.remaining {
    return Err(Ledger(PlanningLimit))
  }
  match @resources.charge_planning(work.ledger, amount) {
    Err(issue) => Err(Ledger(issue))
    Ok(_) => {
      work.remaining -= amount
      Ok(())
    }
  }
}

///|
/// Enumerate finite complete assignments for the unstarted suffix. All
/// transfers are charged per task, including repeated imports of the same CID.
/// Retention uses the checked graph's serial last-consumer lifetime; physical
/// cleanup must still be confirmed by the installed Host before reuse.
pub fn revise_strategy(
  run : CapturedDAG,
  offers : Array[TaskOffer],
  registry : @connector.CapabilityRegistry,
  host_priority : Array[Int]?,
) -> Result[StrategyDecision, SearchIssue] {
  match prepare_strategy_choices(run, offers, registry, host_priority) {
    Ok(choices) => commit_strategy_choice(choices, None)
    Err(issue) => Err(issue)
  }
}

///|
/// Build the feasible set once before consulting a placement policy. No
/// candidate is committed or dispatchable while the choice is pending.
pub fn prepare_strategy_choices(
  run : CapturedDAG,
  offers : Array[TaskOffer],
  registry : @connector.CapabilityRegistry,
  host_priority : Array[Int]?,
) -> Result[StrategyChoiceSet, SearchIssue] {
  prepare_strategy_choices_with_mode(
    run, offers, registry, host_priority, false,
  )
}

///|
/// An opt-in bounded frontier for large adaptive placements. The exhaustive
/// API retains its original limit behavior. Partial search never proves a
/// global optimum or that every assignment is infeasible.
pub fn prepare_bounded_strategy_choices(
  run : CapturedDAG,
  offers : Array[TaskOffer],
  registry : @connector.CapabilityRegistry,
) -> Result[StrategyChoiceSet, SearchIssue] {
  prepare_strategy_choices_with_mode(run, offers, registry, None, true)
}

///|
priv struct SearchFrontier {
  indices : Array[Int]
  duration : Int64
  retention : Int64
}

///|
priv struct BoundedFrontierResult {
  selected : Array[Array[Int]]
  generated : Int
  peak_states : Int
  peak_index_cells : Int
}

///|
fn frontier_duration(offer : TaskOffer) -> Int64 {
  match offer.duration {
    @cost.Complete(value) => value
    @cost.Unknown => 9223372036854775807L
  }
}

///|
fn frontier_add(left : Int64, right : Int64) -> Int64 {
  if right > 9223372036854775807L - left {
    9223372036854775807L
  } else {
    left + right
  }
}

///|
fn bounded_strategy_frontier(
  tasks : Array[Int],
  groups : Array[Array[TaskOffer]],
  max_strategies : Int,
  work : SearchWork,
) -> Result[BoundedFrontierResult, SearchIssue] {
  let mut frontier : Array[SearchFrontier] = [
    { indices: [], duration: 0L, retention: 0L, },
  ]
  let mut generated = 0
  let mut peak_states = 1
  let mut peak_index_cells = 0
  for task in tasks {
    let next : Array[SearchFrontier] = []
    for state in frontier {
      for index, offer in groups[task] {
        match search_charge(work, 1) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        generated += 1
        let indices = state.indices.copy()
        indices.push(index)
        next.push({
          indices,
          duration: frontier_add(state.duration, frontier_duration(offer)),
          retention: frontier_add(
            state.retention,
            offer.capacity.retained_bytes,
          ),
        })
      }
    }
    let live_states = next.length() + frontier.length()
    if live_states > peak_states {
      peak_states = live_states
    }
    let depth = frontier[0].indices.length()
    let live_index_cells = next.length() * (depth + 1) +
      frontier.length() * depth
    if live_index_cells > peak_index_cells {
      peak_index_cells = live_index_cells
    }
    next.sort_by((left, right) => {
      let by_duration = left.duration.compare(right.duration)
      if by_duration != 0 {
        by_duration
      } else {
        let by_retention = left.retention.compare(right.retention)
        if by_retention != 0 {
          by_retention
        } else {
          let mut by_position = 0
          for index in 0..<left.indices.length() {
            if by_position == 0 {
              by_position = left.indices[index].compare(right.indices[index])
            }
          }
          by_position
        }
      }
    })
    let bounded : Array[SearchFrontier] = []
    for index in 0..<next.length() {
      if index >= max_strategies {
        break
      }
      bounded.push(next[index])
    }
    frontier = bounded
  }
  let selected = frontier.map(state => state.indices)
  // The opposite endpoint provides a deterministic late-feasible probe even
  // when every cheap prefix was retained by the duration frontier.
  if max_strategies > 1 {
    let last = tasks.map(task => groups[task].length() - 1)
    let mut present = false
    for candidate in selected {
      if candidate == last {
        present = true
      }
    }
    if !present && !selected.is_empty() {
      selected[selected.length() - 1] = last
    }
  }
  Ok({ selected, generated, peak_states, peak_index_cells, })
}

///|
fn prepare_strategy_choices_with_mode(
  run : CapturedDAG,
  offers : Array[TaskOffer],
  registry : @connector.CapabilityRegistry,
  host_priority : Array[Int]?,
  bounded : Bool,
) -> Result[StrategyChoiceSet, SearchIssue] {
  guard run.search is Some(limits) else { return Err(NotConfigured) }
  if run.stopped {
    return Err(Stopped)
  }
  if run.running is Some(_) || resident_provision_pending(run) {
    return Err(Busy)
  }
  let resources = strategy_search_resources(run)
  if run.searched_generation == Some(run.generation) &&
    run.searched_resources == Some(resources) {
    return Err(UnchangedState)
  }
  if offers.length() > limits.max_offers {
    return Err(OfferLimit)
  }
  let count = run.graph.owners.length()
  let work = { ledger: run.ledger, remaining: limits.max_work, }
  match search_charge(work, count) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match search_charge(work, offers.length()) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let groups : Array[Array[TaskOffer]] = Array::makei(count, _ => [])
  for i, offer in offers {
    if !physical_equal(offer.owner, run.offer_owner) ||
      !physical_equal(offer.owner.graph, run.graph) ||
      offer.task <= 0 ||
      offer.task >= count ||
      task_done(run, offer.task) {
      return Err(ForeignOffer(i))
    }
    if !@connector.capability_registration_matches(offer.registration, registry) {
      return Err(CapabilityUnavailable(i))
    }
    groups[offer.task].push(offer)
  }
  let tasks = []
  let mut combinations = 1
  let mut truncated = false
  for task in 1..<count {
    if task_done(run, task) {
      continue
    }
    if groups[task].is_empty() {
      return Err(MissingTask(task))
    }
    if !truncated &&
      groups[task].length() > limits.max_strategies / combinations {
      if !bounded || host_priority is Some(_) {
        return Err(StrategyLimit)
      }
      truncated = true
      combinations = limits.max_strategies
    } else if !truncated {
      combinations *= groups[task].length()
    }
    tasks.push(task)
  }
  let frontier = if truncated {
    match bounded_strategy_frontier(tasks, groups, combinations, work) {
      Ok(value) => Some(value)
      Err(issue) => return Err(issue)
    }
  } else {
    None
  }
  // Host priority addresses original enumeration positions, before resource
  // rejection. Validate the whole permutation in charged, correctable preflight.
  let positions : Array[Int] = match host_priority {
    None => []
    Some(order) => {
      match search_charge(work, order.length()) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      if order.length() != combinations {
        return Err(InvalidPreference)
      }
      match search_charge(work, combinations) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      let seen = Array::make(combinations, -1)
      for position in order {
        if position < 0 || position >= combinations || seen[position] != -1 {
          return Err(InvalidPreference)
        }
        seen[position] = 0
      }
      seen
    }
  }
  // Only a valid request consumes a search attempt. Invalid requests can be
  // corrected without inventing execution progress; validation work is spent.
  // Once accepted, revoke dispatch before enumeration (including failure).
  run.searched_generation = Some(run.generation)
  run.searched_resources = Some(resources)
  run.strategy = None
  if run.revisions >= limits.max_revisions {
    return Err(RevisionLimit)
  }
  run.revisions += 1
  run.search_report = []
  run.search_report_complete = false
  let indices = Array::make(tasks.length(), 0)
  let feasible : Array[StrategyRevision] = []
  let durations = []
  let usage = @resources.ledger_usage(run.ledger)
  for position in 0..<combinations {
    if truncated {
      guard frontier is Some(frontier) else { return Err(StrategyLimit) }
      let candidate = frontier.selected[position]
      for index in 0..<indices.length() {
        indices[index] = candidate[index]
      }
    }
    match search_charge(work, count) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match search_charge(work, tasks.length()) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    // A deferred revision revokes dispatch, not completed placement history.
    let choices = if run.revision_history.is_empty() {
      Array::make(count, None)
    } else {
      run.revision_history[run.revision_history.length() - 1].choices.copy()
    }
    let mut duration = 0L
    let mut unknown = false
    let mut transfer = 0L
    let mut execution = 0L
    for i, task in tasks {
      let offer = groups[task][indices[i]]
      choices[task] = Some(offer)
      match offer.duration {
        Unknown => unknown = true
        Complete(value) => {
          if value > 9223372036854775807L - duration {
            return Err(Overflow)
          }
          duration += value
        }
      }
      let cap = offer.capacity
      if cap.transfer_bytes > 9223372036854775807L - transfer {
        return Err(Overflow)
      }
      transfer += cap.transfer_bytes
      let task_execution = match offer.resident {
        None => cap.execution_bytes
        Some(profile) => cap.execution_bytes - profile.database_bytes
      }
      if task_execution > execution {
        execution = task_execution
      }
    }
    let retained = match strategy_retention_peak(run, tasks, choices, work) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let shared = match compose_resident_choices(run, choices, work) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if shared.transfer > 9223372036854775807L - transfer ||
      shared.database > 9223372036854775807L - execution {
      return Err(Overflow)
    }
    transfer += shared.transfer
    execution += shared.database
    if shared.execution > execution {
      execution = shared.execution
    }
    match shared.duration {
      Unknown => unknown = true
      Complete(value) => {
        if value > 9223372036854775807L - duration {
          return Err(Overflow)
        }
        duration += value
      }
    }
    let available = @resources.ledger_admission_limits(run.ledger)
    let rejection = if tasks.length() + shared.attempts >
      available.attempts - usage.attempts {
      Some(@resources.AttemptLimit)
    } else if shared.rejected {
      // Resident tables are suballocations of shared execution capacity, not
      // independent completed-output holdings. Keep the rejection domain exact.
      Some(@resources.ExecutionLimit)
    } else if tasks.length() > available.holdings - usage.holdings {
      Some(@resources.HoldingLimit)
    } else if transfer >
      available.transfer_bytes -
      usage.transferred_bytes -
      usage.uncertain_transfer_bytes -
      usage.reserved_transfer_bytes {
      Some(@resources.TransferLimit)
    } else if retained >
      available.retained_bytes -
      usage.held_bytes -
      usage.reserved_retention_bytes {
      Some(@resources.RetentionLimit)
    } else if execution >
      available.execution_bytes - usage.reserved_execution_bytes {
      Some(@resources.ExecutionLimit)
    } else {
      None
    }
    let assessment = {
      position,
      duration: if unknown {
        @cost.Unknown
      } else {
        @cost.Complete(duration)
      },
      rejection,
      transfer_bytes: transfer,
      retained_bytes: retained,
      execution_bytes: execution,
    }
    run.search_report.push(assessment)
    if rejection is None {
      if host_priority is Some(_) {
        positions[position] = feasible.length()
      }
      feasible.push({
        number: run.revisions,
        generation: run.generation,
        choices,
        assessment,
        before: usage,
        search_complete: !truncated,
        estimated_fastest: false,
        selection_source: OfflineLatency,
      })
      durations.push(assessment.duration)
    } else if host_priority is Some(_) {
      positions[position] = -1
    }
    if !truncated {
      let mut digit = indices.length() - 1
      while digit >= 0 {
        indices[digit] += 1
        if indices[digit] < groups[tasks[digit]].length() {
          break
        }
        indices[digit] = 0
        digit -= 1
      }
    }
  }
  if durations.length() > work.remaining / 2 {
    return Err(Ledger(PlanningLimit))
  }
  match search_charge(work, durations.length() * 2) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let feasible_priority = match host_priority {
    None => None
    Some(order) => {
      match search_charge(work, order.length()) {
        Err(e) => return Err(e)
        Ok(_) => ()
      }
      Some(
        order.filter_map(position => {
          let index = positions[position]
          if index < 0 {
            None
          } else {
            Some(index)
          }
        }),
      )
    }
  }
  run.search_report_complete = !truncated
  Ok({
    run,
    registry,
    generation: run.generation,
    resources,
    revision: run.revisions,
    feasible,
    durations,
    priority: feasible_priority,
    diagnostics: {
      complete: !truncated,
      evaluated_assignments: combinations,
      generated_prefixes: frontier.map(value => value.generated).unwrap_or(0),
      peak_frontier_states: frontier
      .map(value => value.peak_states)
      .unwrap_or(0),
      peak_index_cells: frontier
      .map(value => value.peak_index_cells)
      .unwrap_or(0),
    },
    committed: false,
    pending_policy_request: None,
    pending_policy_candidates: None,
  })
}

///|
fn strategy_search_resources(run : CapturedDAG) -> SearchResources {
  let latest = @resources.ledger_usage(run.ledger)
  let admission = @resources.ledger_admission_limits(run.ledger)
  {
    planning_capacity: admission.planning_work,
    attempt_capacity: admission.attempts,
    holding_capacity: admission.holdings,
    attempts: latest.attempts,
    holdings: latest.holdings,
    transferred: latest.transferred_bytes,
    uncertain_transfer: latest.uncertain_transfer_bytes,
    transfer: latest.reserved_transfer_bytes,
    held: latest.held_bytes,
    retention: latest.reserved_retention_bytes,
    execution: latest.reserved_execution_bytes,
  }
}

///|
pub fn strategy_choice_count(choices : StrategyChoiceSet) -> Int {
  choices.feasible.length()
}

///|
pub fn strategy_search_diagnostics(
  choices : StrategyChoiceSet,
) -> StrategySearchDiagnostics {
  choices.diagnostics
}

///|
pub fn strategy_choice_assessment(
  choices : StrategyChoiceSet,
  index : Int,
) -> StrategyAssessment? {
  choices.feasible.get(index).map(choice => choice.assessment)
}

///|
pub fn strategy_choice_registration(
  choices : StrategyChoiceSet,
  index : Int,
  task : Int,
) -> @connector.CapabilityRegistration? {
  choices.feasible
  .get(index)
  .bind(choice => choice.choices.get(task).bind(value => value))
  .map(offer => offer.registration)
}

///|
/// `position` is the planner's immutable candidate position. Exhaustive search
/// uses the original complete-assignment order; a bounded frontier uses its
/// selected candidate order. Invalid or stale responses never fall back to a
/// different candidate. `None` applies the offline latency policy.
pub fn commit_strategy_choice(
  choices : StrategyChoiceSet,
  position : Int?,
) -> Result[StrategyDecision, SearchIssue] {
  commit_strategy_choice_with_source(
    choices,
    position,
    if position is Some(_) {
      HostProposal
    } else if choices.run.search_report_complete {
      OfflineLatency
    } else {
      BoundedLatency
    },
  )
}

///|
/// Mint one bounded consultation for this choice set. The Host authenticates
/// the policy peer and retains this request across the I/O boundary.
pub fn prepare_strategy_policy_request(
  choices : StrategyChoiceSet,
  request_id : String,
  run_identity : String,
  authority : String,
  deadline_ms : Int64,
  now_ms : Int64,
) -> Result[PolicyRequest, SearchIssue] {
  for value in [request_id, run_identity, authority] {
    if value.is_empty() || value.length() > 128 {
      return Err(InvalidPreference)
    }
  }
  if deadline_ms <= now_ms || choices.committed {
    return Err(InvalidPreference)
  }
  if choices.pending_policy_request is Some(_) {
    return Err(InvalidPreference)
  }
  match
    @resources.charge_planning(choices.run.ledger, choices.feasible.length()) {
    Ok(_) => ()
    Err(issue) => return Err(Ledger(issue))
  }
  let candidates = match strategy_policy_candidate_set(choices) {
    Ok(candidates) => candidates
    Err(issue) => return Err(issue)
  }
  let request = {
    version: "actql-placement-policy/0.1",
    request_id,
    run_identity,
    authority,
    candidate_set_cid: candidates.cid,
    generation: choices.generation,
    revision: choices.revision,
    deadline_ms,
  }
  choices.pending_policy_request = Some(request)
  choices.pending_policy_candidates = Some(candidates)
  Ok(request)
}

///|
/// Only a minted consultation can expose its immutable candidate projection.
pub fn strategy_policy_candidates(
  choices : StrategyChoiceSet,
) -> PolicyCandidateSet? {
  choices.pending_policy_candidates
}

///|
/// Reject a stale, cross-Run, expired or altered response before common
/// feasibility and dispatch checks. Authentication belongs to the Host adapter.
pub fn commit_strategy_policy_decision(
  choices : StrategyChoiceSet,
  request : PolicyRequest,
  response : PolicyResponse,
  now_ms : Int64,
) -> Result[StrategyDecision, SearchIssue] {
  if choices.pending_policy_request != Some(request) ||
    response.request != request ||
    request.version != "actql-placement-policy/0.1" ||
    now_ms > request.deadline_ms ||
    response.policy_id.is_empty() ||
    response.policy_id.length() > 128 ||
    response.policy_revision.is_empty() ||
    response.policy_revision.length() > 128 ||
    response.explanation.length() > 1024 {
    return Err(InvalidPreference)
  }
  commit_strategy_choice_with_source(
    choices,
    Some(response.position),
    ExternalPolicy({
      policy_id: response.policy_id,
      revision: response.policy_revision,
      request_id: request.request_id,
      explanation: response.explanation,
    }),
  )
}

///|
fn commit_strategy_choice_with_source(
  choices : StrategyChoiceSet,
  position : Int?,
  source : StrategySelectionSource,
) -> Result[StrategyDecision, SearchIssue] {
  let run = choices.run
  if choices.committed ||
    run.stopped ||
    run.running is Some(_) ||
    resident_provision_pending(run) ||
    run.generation != choices.generation ||
    run.revisions != choices.revision ||
    run.searched_generation != Some(choices.generation) ||
    run.searched_resources != Some(choices.resources) ||
    strategy_search_resources(run) != choices.resources ||
    run.strategy is Some(_) {
    return Err(StaleChoice)
  }
  let selected = match position {
    Some(position) => {
      let mut found = None
      for index, candidate in choices.feasible {
        if candidate.assessment.position == position {
          found = Some(index)
          break
        }
      }
      guard found is Some(index) else { return Err(InvalidPreference) }
      Some((index, false))
    }
    None =>
      match
        @cost.choose_serial(
          choices.durations,
          choices.priority,
          choices.durations.length() * 2,
        ) {
        Err(issue) => return Err(Cost(issue))
        Ok(NoCandidates) => {
          choices.committed = true
          return Ok(
            if run.search_report_complete {
              NoFeasible
            } else {
              Deferred
            },
          )
        }
        Ok(Deferred) => {
          choices.committed = true
          return Ok(Deferred)
        }
        Ok(EstimatedFastest(index, _)) =>
          Some((index, run.search_report_complete))
        Ok(HostPreferred(index)) => Some((index, false))
      }
  }
  guard selected is Some((index, estimated_fastest)) else {
    return Err(InvalidPreference)
  }
  for task, offer in choices.feasible[index].choices {
    if !task_done(run, task) &&
      offer is Some(offer) &&
      (
        !@connector.capability_registration_matches(
          offer.registration,
          choices.registry,
        ) ||
        !@connector.capability_registration_available(offer.registration)
      ) {
      return Err(CapabilityUnavailable(task))
    }
  }
  choices.committed = true
  let revision = {
    ..choices.feasible[index],
    estimated_fastest,
    selection_source: source,
  }
  run.strategy = Some(revision)
  run.revision_history.push(revision)
  Ok(Selected(revision))
}

///|
fn strategy_candidate_matches(
  run : CapturedDAG,
  task : Int,
  candidate : @connector.FixedComputeCandidate,
) -> Bool {
  if run.search is None {
    return true
  }
  guard run.strategy is Some(revision) &&
    revision.choices.get(task).bind(value => value) is Some(offer) else {
    return false
  }
  physical_equal(
    offer.registration,
    @connector.fixed_compute_candidate_registration(candidate),
  )
}

///|
/// Managed and legacy candidates share the selected implementation identity,
/// but never share or coerce their request payloads.
fn[T] strategy_managed_candidate_matches(
  run : CapturedDAG,
  task : Int,
  candidate : @connector.ManagedFixedComputeCandidate[T],
) -> Bool {
  if run.managed_selections.get(task).bind(value => value) is Some(selected) {
    return physical_equal(
      selected,
      @connector.managed_fixed_compute_candidate_registration(candidate),
    )
  }
  if run.search is None {
    return true
  }
  guard run.strategy is Some(revision) &&
    revision.choices.get(task).bind(value => value) is Some(offer) else {
    return false
  }
  physical_equal(
    offer.registration,
    @connector.managed_fixed_compute_candidate_registration(candidate),
  )
}

///|
/// Peak additional result holding for the remaining serial graph. Internal
/// results stop contributing after their last checked consumer. Sink results
/// remain live for the caller. A Stage publication is the checked port used by
/// graph edges, so it is not by itself an external-retention obligation. This
/// models retention only, never Store cleanup confirmation or current use
/// authority.
fn strategy_retention_peak(
  run : CapturedDAG,
  tasks : Array[Int],
  choices : Array[TaskOffer?],
  work : SearchWork,
) -> Result[Int64, SearchIssue] {
  let live = Array::make(run.graph.owners.length(), 0L)
  let mut held = 0L
  let mut peak = 0L
  for task in tasks {
    guard choices.get(task).bind(value => value) is Some(offer) else {
      return Err(MissingTask(task))
    }
    if offer.capacity.retained_bytes > 9223372036854775807L - held {
      return Err(Overflow)
    }
    held += offer.capacity.retained_bytes
    live[task] = offer.capacity.retained_bytes
    if held > peak {
      peak = held
    }
    for producer in tasks {
      if producer > task || live[producer] == 0L {
        continue
      }
      let mut has_consumer = false
      let mut needed = false
      for edge in run.graph.data {
        match search_charge(work, 1) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        if edge.producer == producer {
          has_consumer = true
          if edge.consumer > task {
            needed = true
          }
        }
      }
      if has_consumer && !needed {
        held -= live[producer]
        live[producer] = 0L
      }
    }
  }
  Ok(peak)
}

///|
pub fn strategy_assessment(revision : StrategyRevision) -> StrategyAssessment {
  revision.assessment
}

///|
pub fn strategy_selection_source(
  revision : StrategyRevision,
) -> StrategySelectionSource {
  revision.selection_source
}

///|
pub fn strategy_usage_before(
  revision : StrategyRevision,
) -> @resources.LedgerUsage {
  revision.before
}

///|
pub fn strategy_registration(
  revision : StrategyRevision,
  task : Int,
) -> @connector.CapabilityRegistration? {
  revision.choices
  .get(task)
  .bind(value => value)
  .map(offer => offer.registration)
}

///|
pub fn strategy_revision_number(revision : StrategyRevision) -> Int {
  revision.number
}

///|
pub fn strategy_generation(revision : StrategyRevision) -> Int {
  revision.generation
}

///|
pub fn strategy_task_envelope(
  run : CapturedDAG,
  task : Int,
) -> PhysicalEnvelope? {
  run.strategy
  .bind(revision => revision.choices.get(task).bind(value => value))
  .map(offer => offer.capacity)
}

///|
pub fn strategy_report_count(run : CapturedDAG) -> Int {
  run.search_report.length()
}

///|
pub fn strategy_report_at(
  run : CapturedDAG,
  index : Int,
) -> StrategyAssessment? {
  run.search_report.get(index)
}

///|
pub fn strategy_history_count(run : CapturedDAG) -> Int {
  run.revision_history.length()
}

///|
pub fn strategy_history_at(run : CapturedDAG, index : Int) -> StrategyRevision? {
  run.revision_history.get(index)
}
