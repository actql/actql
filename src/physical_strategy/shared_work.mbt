///|
/// Bounded, checked physical-work inventory supplied by an implementation.
/// Slots are local accounting addresses, not semantic obligations or provider
/// categories. Preparing this estimate does not allocate an execution resource.
struct SharedWorkEstimate {
  owner : StrategyOfferOwner
  slots : Int
  lines : Array[@cost.SerialEstimateLine]
  duration : @cost.DurationEstimate
}

///|
pub fn prepare_shared_work(
  run : CapturedDAG,
  slots : Int,
  lines : Array[@cost.SerialEstimateLine],
  max_entries : Int,
) -> Result[SharedWorkEstimate, SearchIssue] {
  if slots < 0 || max_entries < 0 {
    return Err(InvalidCapacity)
  }
  if slots > max_entries || lines.length() > max_entries - slots {
    return Err(OfferLimit)
  }
  let mut remaining = max_entries - slots - lines.length()
  match @resources.charge_planning(run.ledger, slots + lines.length()) {
    Err(issue) => return Err(Ledger(issue))
    Ok(_) => ()
  }
  for line in lines {
    if line.work_slots.length() > remaining {
      return Err(OfferLimit)
    }
    remaining -= line.work_slots.length()
    match @resources.charge_planning(run.ledger, line.work_slots.length()) {
      Err(issue) => return Err(Ledger(issue))
      Ok(_) => ()
    }
  }
  let duration = match @cost.assess_serial(slots, lines, max_entries) {
    Err(issue) => return Err(Cost(issue))
    Ok(value) => value
  }
  Ok({
    owner: run.offer_owner,
    slots,
    lines: lines.map(line => { ..line, work_slots: line.work_slots.copy(), }),
    duration,
  })
}

///|
pub fn shared_work_duration(
  work : SharedWorkEstimate,
) -> @cost.DurationEstimate {
  work.duration
}
