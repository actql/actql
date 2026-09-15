///|
pub(all) struct SearchLimits {
  max_offers : Int
  max_strategies : Int
  max_work : Int
  max_revisions : Int
}

///|
priv struct SearchResources {
  attempts : Int
  holdings : Int
  transferred : Int64
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
struct StrategyRevision {
  number : Int
  generation : Int
  choices : Array[TaskOffer?]
  assessment : StrategyAssessment
  before : @resources.LedgerUsage
  estimated_fastest : Bool
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
/// Retention sums declared capacities conservatively; no last-use discount is
/// taken until allocation sharing/release is actually implemented and proven.
pub fn revise_strategy(
  run : CapturedDAG,
  offers : Array[TaskOffer],
  registry : @connector.CapabilityRegistry,
  host_priority : Array[Int]?,
) -> Result[StrategyDecision, SearchIssue] {
  guard run.search is Some(limits) else { return Err(NotConfigured) }
  if run.stopped {
    return Err(Stopped)
  }
  if run.running is Some(_) || resident_provision_pending(run) {
    return Err(Busy)
  }
  let latest = @resources.ledger_usage(run.ledger)
  let resources = {
    attempts: latest.attempts,
    holdings: latest.holdings,
    transferred: latest.transferred_bytes,
    transfer: latest.reserved_transfer_bytes,
    held: latest.held_bytes,
    retention: latest.reserved_retention_bytes,
    execution: latest.reserved_execution_bytes,
  }
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
  for task in 1..<count {
    if task_done(run, task) {
      continue
    }
    if groups[task].is_empty() {
      return Err(MissingTask(task))
    }
    if groups[task].length() > limits.max_strategies / combinations {
      return Err(StrategyLimit)
    }
    combinations *= groups[task].length()
    tasks.push(task)
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
    let mut retained = 0L
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
      if cap.transfer_bytes > 9223372036854775807L - transfer ||
        cap.retained_bytes > 9223372036854775807L - retained {
        return Err(Overflow)
      }
      transfer += cap.transfer_bytes
      retained += cap.retained_bytes
      let task_execution = match offer.resident {
        None => cap.execution_bytes
        Some(profile) => cap.execution_bytes - profile.database_bytes
      }
      if task_execution > execution {
        execution = task_execution
      }
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
    let available = @resources.ledger_limits(run.ledger)
    let rejection = if tasks.length() + shared.attempts >
      available.attempts - usage.attempts {
      Some(@resources.AttemptLimit)
    } else if shared.rejected {
      Some(@resources.RetentionLimit)
    } else if tasks.length() > available.holdings - usage.holdings {
      Some(@resources.HoldingLimit)
    } else if transfer >
      available.transfer_bytes -
      usage.transferred_bytes -
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
        estimated_fastest: false,
      })
      durations.push(assessment.duration)
    } else if host_priority is Some(_) {
      positions[position] = -1
    }
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
  match
    @cost.choose_serial(durations, feasible_priority, durations.length() * 2) {
    Err(issue) => Err(Cost(issue))
    Ok(NoCandidates) => {
      run.search_report_complete = true
      run.strategy = None
      Ok(NoFeasible)
    }
    Ok(Deferred) => {
      run.search_report_complete = true
      run.strategy = None
      Ok(Deferred)
    }
    Ok(EstimatedFastest(index, _)) => {
      run.search_report_complete = true
      let selected = { ..feasible[index], estimated_fastest: true, }
      run.strategy = Some(selected)
      run.revision_history.push(selected)
      Ok(Selected(selected))
    }
    Ok(HostPreferred(index)) => {
      run.search_report_complete = true
      let selected = feasible[index]
      run.strategy = Some(selected)
      run.revision_history.push(selected)
      Ok(Selected(selected))
    }
  }
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
pub fn strategy_assessment(revision : StrategyRevision) -> StrategyAssessment {
  revision.assessment
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
