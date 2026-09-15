///|
/// Per-producer physical import, including its real transfer and scratch. This
/// estimate never discharges input guards or asserts that a table exists.
pub(all) struct ResidentImportEstimate {
  milliseconds : Int64?
  transfer_bytes : Int64
  scratch_bytes : Int64
  table_bytes : Int64
}

///|
struct ResidentProfile {
  owner : StrategyOfferOwner
  implementation : @connector.CapabilityRegistration
  database_bytes : Int64
  preparation_ms : Int64?
  cleanup_ms : Int64?
  imports : Array[ResidentImportEstimate]
}

///|
pub fn strategy_resident_profile(
  revision : StrategyRevision,
  task : Int,
) -> ResidentProfile? {
  revision.choices.get(task).bind(value => value).bind(offer => offer.resident)
}

///|
pub fn resident_profile_import(
  profile : ResidentProfile,
  producer : Int,
) -> ResidentImportEstimate? {
  profile.imports.get(producer)
}

///|
pub fn resident_profile_matches(
  run : CapturedDAG,
  profile : ResidentProfile,
) -> Bool {
  physical_equal(run.offer_owner, profile.owner)
}

///|
/// Implementation identity is separate from this particular resource profile.
/// Equal connector names or equal capacity estimates do not establish ownership.
pub fn resident_profile_registration(
  profile : ResidentProfile,
) -> @connector.CapabilityRegistration {
  profile.implementation
}

///|
pub fn prepare_resident_profile(
  run : CapturedDAG,
  implementation : @connector.CapabilityRegistration,
  database_bytes : Int64,
  preparation_ms : Int64?,
  cleanup_ms : Int64?,
  imports : Array[ResidentImportEstimate],
) -> Result[ResidentProfile, SearchIssue] {
  if !@connector.capability_registration_available(implementation) ||
    !@connector.capability_description(implementation).fixed_compute {
    return Err(InvalidCapacity)
  }
  if database_bytes <= 0L || imports.length() != run.graph.owners.length() {
    return Err(InvalidCapacity)
  }
  match @resources.charge_planning(run.ledger, imports.length()) {
    Err(issue) => return Err(Ledger(issue))
    Ok(_) => ()
  }
  if (preparation_ms is Some(value) && value < 0L) ||
    (cleanup_ms is Some(value) && value < 0L) {
    return Err(InvalidCapacity)
  }
  for item in imports {
    if item.transfer_bytes <= 0L ||
      item.scratch_bytes <= 0L ||
      item.table_bytes <= 0L ||
      (item.milliseconds is Some(value) && value < 0L) {
      return Err(InvalidCapacity)
    }
  }
  Ok({
    owner: run.offer_owner,
    implementation,
    database_bytes,
    preparation_ms,
    cleanup_ms,
    imports: imports.copy(),
  })
}

///|
/// Task lines include its calculation, receiving validation, output transfer,
/// Host retention and task cleanup. DB setup and input import are added once by
/// whole-plan composition; they must not also appear in these task-only lines.
pub fn resident_task_offer(
  run : CapturedDAG,
  offer : TaskOffer,
  profile : ResidentProfile,
  output_bytes : Int64,
) -> Result[TaskOffer, SearchIssue] {
  if !physical_equal(run.offer_owner, offer.owner) ||
    !physical_equal(run.offer_owner, profile.owner) ||
    !physical_equal(offer.registration, profile.implementation) {
    return Err(ForeignOffer(offer.task))
  }
  if output_bytes < 0L ||
    offer.capacity.execution_bytes < profile.database_bytes {
    return Err(InvalidCapacity)
  }
  Ok({ ..offer, resident: Some(profile), resident_output_bytes: output_bytes, })
}

///|
priv struct ResidentComposition {
  duration : @cost.DurationEstimate
  transfer : Int64
  execution : Int64
  database : Int64
  attempts : Int
  rejected : Bool
}

///|
fn compose_resident_choices(
  run : CapturedDAG,
  choices : Array[TaskOffer?],
  work : SearchWork,
) -> Result[ResidentComposition, SearchIssue] {
  let mut profile : ResidentProfile? = None
  for task, choice in choices {
    if task_done(run, task) {
      continue
    }
    if choice is Some(offer) && offer.resident is Some(actual) {
      if profile is Some(previous) && !physical_equal(previous, actual) {
        return Err(InvalidCapacity)
      }
      profile = Some(actual)
    }
  }
  // An existing environment's outstanding cleanup belongs to every candidate,
  // including all-Local plans and plans made while cleanup is still pending.
  let outstanding_cleanup = match run.resident_environment {
    Some(env) if !env.settled => env.profile.map(value => value.cleanup_ms)
    _ => None
  }
  guard profile is Some(profile) else {
    return Ok({
      duration: match outstanding_cleanup {
        Some(Some(value)) => @cost.Complete(value)
        Some(None) => @cost.Unknown
        None => @cost.Complete(0L)
      },
      transfer: 0L,
      execution: 0L,
      database: 0L,
      attempts: 0,
      rejected: false,
    })
  }
  let live = run.resident_environment is Some(env) &&
    resident_environment_available(run, env) &&
    env.profile is Some(actual) &&
    physical_equal(actual, profile)
  let available = Array::make(choices.length(), false)
  let table_bytes = Array::make(choices.length(), 0L)
  let finished = Array::make(choices.length(), false)
  for task in 0..<choices.length() {
    finished[task] = task_done(run, task)
  }
  let mut held = 0L
  let mut rejected = false
  if live && run.resident_environment is Some(env) {
    for i, table in env.tables {
      if table is Some(table) &&
        table.committed &&
        !@resources.shared_allocation_usage(table.allocation).retiring {
        available[i] = true
        table_bytes[i] = @resources.shared_allocation_usage(table.allocation).bytes
      }
    }
    held = @resources.shared_capacity_usage(env.capacity).allocated
  }
  let lines = []
  if outstanding_cleanup is Some(cleanup) {
    lines.push(cleanup)
  }
  if !live {
    lines.push(profile.preparation_ms)
    lines.push(profile.cleanup_ms)
  }
  let mut transfer = 0L
  let mut scratch = 0L
  let mut attempts = if live { 0 } else { 1 }
  for task, choice in choices {
    if task_done(run, task) {
      continue
    }
    finished[task] = true
    match search_charge(work, run.graph.data.length() + 1) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    guard choice is Some(offer) && offer.resident is Some(_) else { continue }
    for edge in run.graph.data {
      if edge.consumer != task {
        continue
      }
      if !available[edge.producer] {
        let imported = profile.imports[edge.producer]
        lines.push(imported.milliseconds)
        if transfer > 9223372036854775807L - imported.transfer_bytes {
          return Err(Overflow)
        }
        transfer += imported.transfer_bytes
        if imported.scratch_bytes > scratch {
          scratch = imported.scratch_bytes
        }
        attempts += 1
        if imported.table_bytes > profile.database_bytes - held {
          rejected = true
        } else {
          held += imported.table_bytes
          table_bytes[edge.producer] = imported.table_bytes
        }
        available[edge.producer] = true
      }
    }
    // The implementation declares this physical representation independently
    // from its Host result. Equal logical contents do not imply equal sizes.
    let output_fits = offer.resident_output_bytes <=
      profile.database_bytes - held
    if !output_fits {
      rejected = true
    } else {
      held += offer.resident_output_bytes
    }
    // Match transaction cleanup: reserve the new result before releasing any
    // previous table, and retain inputs through all still-unstarted consumers.
    // Current output is published only after that cleanup and is not eligible
    // for DROP in its own transaction.
    for producer in 0..<available.length() {
      if !available[producer] {
        continue
      }
      match search_charge(work, run.graph.data.length() + 1) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let mut needed = false
      for edge in run.graph.data {
        if edge.producer == producer && !finished[edge.consumer] {
          needed = true
        }
      }
      if !needed {
        held -= table_bytes[producer]
        table_bytes[producer] = 0L
        available[producer] = false
      }
    }
    table_bytes[task] = if output_fits {
      offer.resident_output_bytes
    } else {
      0L
    }
    available[task] = true
  }
  let mut duration = 0L
  let mut unknown = false
  for line in lines {
    match line {
      None => unknown = true
      Some(value) => {
        if value > 9223372036854775807L - duration {
          return Err(Overflow)
        }
        duration += value
      }
    }
  }
  let database = if live { 0L } else { profile.database_bytes }
  if scratch > 9223372036854775807L - database {
    return Err(Overflow)
  }
  Ok({
    duration: if unknown {
      @cost.Unknown
    } else {
      @cost.Complete(duration)
    },
    transfer,
    execution: database + scratch,
    database,
    attempts,
    rejected,
  })
}
