///|
/// Per-producer physical import, including its real transfer and scratch. This
/// estimate never discharges input guards or asserts that a table exists.
pub(all) struct ResidentImportEstimate {
  work : SharedWorkEstimate
  transfer_bytes : Int64
  scratch_bytes : Int64
  table_bytes : Int64
}

///|
struct ResidentProfile {
  owner : StrategyOfferOwner
  binding : @connector.ResourceBinding
  database_bytes : Int64
  preparation : SharedWorkEstimate
  cleanup : SharedWorkEstimate
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
  @connector.resource_binding_registration(profile.binding)
}

///|
pub fn resident_profile_resource_binding(
  profile : ResidentProfile,
) -> @connector.ResourceBinding {
  profile.binding
}

///|
pub fn prepare_resident_profile(
  run : CapturedDAG,
  binding : @connector.ResourceBinding,
  database_bytes : Int64,
  preparation : SharedWorkEstimate,
  cleanup : SharedWorkEstimate,
  imports : Array[ResidentImportEstimate],
) -> Result[ResidentProfile, SearchIssue] {
  let implementation = @connector.resource_binding_registration(binding)
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
  if !physical_equal(run.offer_owner, preparation.owner) ||
    !physical_equal(run.offer_owner, cleanup.owner) {
    return Err(InvalidCapacity)
  }
  for item in imports {
    if item.transfer_bytes <= 0L ||
      item.scratch_bytes <= 0L ||
      item.table_bytes <= 0L ||
      !physical_equal(run.offer_owner, item.work.owner) {
      return Err(InvalidCapacity)
    }
  }
  Ok({
    owner: run.offer_owner,
    binding,
    database_bytes,
    preparation,
    cleanup,
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
    !physical_equal(offer.registration, resident_profile_registration(profile)) {
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
fn compose_resident_profile(
  run : CapturedDAG,
  choices : Array[TaskOffer?],
  profile : ResidentProfile,
  work : SearchWork,
) -> Result[ResidentComposition, SearchIssue] {
  let mut environment : ResidentEnvironment? = None
  for env in run.resident_environments {
    match search_charge(work, 1) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    if env.profile is Some(actual) && physical_equal(actual, profile) {
      environment = Some(env)
      break
    }
  }
  let live = environment is Some(env) &&
    resident_environment_available(run, env)
  let available = Array::make(choices.length(), false)
  let table_bytes = Array::make(choices.length(), 0L)
  let finished = Array::make(choices.length(), false)
  for task in 0..<choices.length() {
    finished[task] = task_done(run, task)
  }
  let mut held = 0L
  let mut rejected = false
  if live && environment is Some(env) {
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
  if !live {
    lines.push(profile.preparation.duration)
    lines.push(profile.cleanup.duration)
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
    guard choice is Some(offer) &&
      offer.resident is Some(selected) &&
      physical_equal(selected, profile) else {
      continue
    }
    for edge in run.graph.data {
      if edge.consumer != task {
        continue
      }
      if !available[edge.producer] {
        let imported = profile.imports[edge.producer]
        lines.push(imported.work.duration)
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
      Unknown => unknown = true
      Complete(value) => {
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
