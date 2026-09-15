///|
/// Compose distinct resource bindings without treating equal implementation IDs
/// or equal producer contents as proof that a physical copy is shared.
fn compose_resident_choices(
  run : CapturedDAG,
  choices : Array[TaskOffer?],
  work : SearchWork,
) -> Result[ResidentComposition, SearchIssue] {
  let profiles : Array[ResidentProfile] = []
  for task, choice in choices {
    if task_done(run, task) {
      continue
    }
    guard choice is Some(offer) && offer.resident is Some(profile) else {
      continue
    }
    let mut found = false
    for prior in profiles {
      match search_charge(work, 1) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      if physical_equal(prior, profile) {
        found = true
        break
      }
      if physical_equal(prior.binding, profile.binding) {
        // A single binding cannot promise two incompatible resource profiles.
        return Err(InvalidCapacity)
      }
    }
    if !found {
      profiles.push(profile)
    }
  }
  let durations : Array[@cost.DurationEstimate] = []
  for env in run.resident_environments {
    match search_charge(work, 1) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    if !env.settled && env.profile is Some(profile) {
      // Recovery responsibility survives selection of other bindings or Local.
      durations.push(profile.cleanup.duration)
    }
  }
  let mut transfer = 0L
  let mut database = 0L
  let mut scratch = 0L
  let mut attempts = 0
  let mut rejected = false
  for profile in profiles {
    let part = match compose_resident_profile(run, choices, profile, work) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if part.transfer > 9223372036854775807L - transfer ||
      part.database > 9223372036854775807L - database ||
      part.attempts > 2147483647 - attempts {
      return Err(Overflow)
    }
    transfer += part.transfer
    database += part.database
    let temporary = part.execution - part.database
    if temporary > scratch {
      scratch = temporary
    }
    attempts += part.attempts
    rejected = rejected || part.rejected
    durations.push(part.duration)
  }
  let mut duration = 0L
  let mut unknown = false
  for item in durations {
    match item {
      Unknown => unknown = true
      Complete(value) => {
        if value > 9223372036854775807L - duration {
          return Err(Overflow)
        }
        duration += value
      }
    }
  }
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
