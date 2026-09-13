///|
struct FixedComputeCandidate {
  request : FixedComputeRequest
  registration : CapabilityRegistration
  duration : @cost.DurationEstimate
  quantities : QueryQuantities
}

///|
struct PreparedCompute[T] {
  candidate : FixedComputeCandidate
  payload : T
}

///|
struct FixedComputeChoice {
  candidate : FixedComputeCandidate
  reason : @cost.CostChoice
}

///|
pub enum FixedComputeSelection {
  Proposed(FixedComputeChoice)
  Deferred
  NoCandidates
}

///|
fn[T] bind_compute_candidate(
  registration : CapabilityRegistration,
  request : FixedComputeRequest,
  payload : T,
  work_slots : Int,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : QueryQuantities,
  max_entries : Int,
) -> Result[PreparedCompute[T], FixedComputeIssue] {
  if !registration.owner.live {
    return Err(CapabilityClosed)
  }
  if !registration.description.fixed_compute {
    return Err(ComputeUnsupported)
  }
  if !valid_quantity(quantities.transfer_bytes) ||
    !valid_quantity(quantities.retained_bytes) ||
    !valid_quantity(quantities.money_units) {
    return Err(NegativeQuantity)
  }
  match @cost.assess_serial(work_slots, estimates, max_entries) {
    Err(issue) => Err(Cost(issue))
    Ok(duration) =>
      Ok({
        candidate: { request, registration, duration, quantities, },
        payload,
      })
  }
}

///|
pub fn[T] prepared_compute_candidate(
  value : PreparedCompute[T],
) -> FixedComputeCandidate {
  value.candidate
}

///|
pub fn[T] fixed_compute_choice_payload(
  choice : FixedComputeChoice,
  prepared : PreparedCompute[T],
) -> T? {
  if prepared.candidate.registration.owner.live &&
    physical_equal(choice.candidate, prepared.candidate) {
    Some(prepared.payload)
  } else {
    None
  }
}

///|
/// Pure candidate comparison. No input consumption, source access, reservation
/// or completion evidence. Unknown work stays unknown, including input transfer.
pub fn choose_fixed_compute_candidate(
  registry : CapabilityRegistry,
  request : FixedComputeRequest,
  candidates : Array[FixedComputeCandidate],
  host_priority : Array[Int]?,
  max_entries : Int,
) -> Result[FixedComputeSelection, FixedComputeIssue] {
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
  if candidates.length() > max_entries {
    return Err(PlanningLimit)
  }
  let durations = []
  for i, candidate in candidates {
    if !physical_equal(candidate.request, request) {
      return Err(ForeignRequest(i))
    }
    if !capability_registration_matches(candidate.registration, registry) {
      return Err(ForeignCapability(i))
    }
    durations.push(candidate.duration)
  }
  @cost.choose_serial(
    durations,
    host_priority,
    max_entries - candidates.length(),
  )
  .map_err(issue => FixedComputeIssue::Cost(issue))
  .map(reason => {
    match reason {
      NoCandidates => NoCandidates
      Deferred => Deferred
      EstimatedFastest(index, _) | HostPreferred(index) =>
        Proposed({ candidate: candidates[index], reason, })
    }
  })
}

///|
pub fn fixed_compute_choice_reason(
  choice : FixedComputeChoice,
) -> @cost.CostChoice {
  choice.reason
}

///|
pub fn fixed_compute_candidate_duration(
  candidate : FixedComputeCandidate,
) -> @cost.DurationEstimate {
  candidate.duration
}

///|
pub fn fixed_compute_candidate_quantities(
  candidate : FixedComputeCandidate,
) -> QueryQuantities {
  candidate.quantities
}
