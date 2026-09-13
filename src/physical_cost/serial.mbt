///|
/// An estimate for a disjoint group of physical work slots. Slots are local
/// accounting addresses, never canonical occurrences or evidence identities.
pub(all) struct SerialEstimateLine {
  work_slots : Array[Int]
  milliseconds : Int64?
}

///|
pub(all) enum DurationEstimate {
  Complete(Int64)
  Unknown
} derive(Eq, Debug)

///|
pub enum CostIssue {
  InvalidLimit
  PlanningLimit
  EmptyCoverage(Int)
  InvalidSlot(Int, Int)
  DuplicateSlot(Int)
  NegativeDuration(Int)
  DurationOverflow
  InvalidPreference
} derive(Eq, Debug)

///|
/// A cost decision is NOT semantic admission, a reservation or a dispatch token.
pub enum CostChoice {
  NoCandidates
  EstimatedFastest(Int, Int64)
  HostPreferred(Int)
  Deferred
} derive(Eq, Debug)

///|
/// Compose estimates for serial work, with no overlap/streaming assumed.
/// The caller supplies the complete work inventory, including acquisition,
/// compute, transfer, conversion, capture, retention and cleanup as applicable.
/// A bundle covers several slots once; adding its breakdown again is invalid.
/// Missing slots or missing durations make the total unknown, not zero.
/// Invalid estimates do not imply that the corresponding capability is absent.
pub fn assess_serial(
  required_work : Int,
  lines : Array[SerialEstimateLine],
  max_entries : Int,
) -> Result[DurationEstimate, CostIssue] {
  if required_work < 0 || max_entries < 0 {
    return Err(InvalidLimit)
  }
  // Charge the inventory and outer list before allocating or traversing them.
  if required_work > max_entries || lines.length() > max_entries - required_work {
    return Err(PlanningLimit)
  }
  let mut remaining = max_entries - required_work - lines.length()
  let seen : Map[Int, Bool] = Map([])
  let mut total = 0L
  let mut unknown = false
  for i = 0; i < lines.length(); i = i + 1 {
    let line = lines[i]
    if line.work_slots.length() > remaining {
      return Err(PlanningLimit)
    }
    remaining -= line.work_slots.length()
    if line.work_slots.is_empty() {
      return Err(EmptyCoverage(i))
    }
    for slot in line.work_slots {
      if slot < 0 || slot >= required_work {
        return Err(InvalidSlot(i, slot))
      }
      if seen.contains(slot) {
        return Err(DuplicateSlot(slot))
      }
      seen[slot] = true
    }
    match line.milliseconds {
      None => unknown = true
      Some(value) => {
        if value < 0L {
          return Err(NegativeDuration(i))
        }
        if value > 9223372036854775807L - total {
          return Err(DurationOverflow)
        }
        total += value
      }
    }
  }
  if unknown || seen.length() != required_work {
    Ok(Unknown)
  } else {
    Ok(Complete(total))
  }
}

///|
/// Rank an already eligible candidate set by serial estimated latency.
/// The caller must separately establish meaning, authority, enforceable limits
/// and retention. Even Complete(0) is only a supplied estimate.
/// If any estimate is unknown, no global fastest claim is possible: use a
/// supplied complete permutation of candidate positions, or defer.
/// Equal complete estimates use Host priority when supplied; otherwise they
/// retain candidate enumeration order. A full ordering can rank any tied subset.
/// No I/O, acquisition, fallback execution, or resource reservation occurs here.
pub fn choose_serial(
  estimates : Array[DurationEstimate],
  host_priority : Array[Int]?,
  max_entries : Int,
) -> Result[CostChoice, CostIssue] {
  if max_entries < 0 {
    return Err(InvalidLimit)
  }
  if estimates.length() > max_entries {
    return Err(PlanningLimit)
  }
  match host_priority {
    Some(order) => {
      if order.length() > max_entries - estimates.length() {
        return Err(PlanningLimit)
      }
      if order.length() != estimates.length() {
        return Err(InvalidPreference)
      }
      let seen : Map[Int, Bool] = Map([])
      for index in order {
        if index < 0 || index >= estimates.length() || seen.contains(index) {
          return Err(InvalidPreference)
        }
        seen[index] = true
      }
    }
    None => ()
  }
  if estimates.is_empty() {
    return Ok(NoCandidates)
  }
  let mut unknown = false
  let mut best = 0
  let mut duration = 9223372036854775807L
  for i = 0; i < estimates.length(); i = i + 1 {
    match estimates[i] {
      Unknown => unknown = true
      Complete(value) => {
        if value < 0L {
          return Err(NegativeDuration(i))
        }
        if value < duration {
          duration = value
          best = i
        }
      }
    }
  }
  if unknown {
    match host_priority {
      Some(order) => Ok(HostPreferred(order[0]))
      None => Ok(Deferred)
    }
  } else {
    if host_priority is Some(order) {
      for index in order {
        if estimates[index] == Complete(duration) {
          return Ok(EstimatedFastest(index, duration))
        }
      }
    }
    Ok(EstimatedFastest(best, duration))
  }
}
