///|
/// Managed-profile candidate with the same registration and cost semantics as
/// legacy fixed Compute, but an explicitly different input contract.
struct ManagedFixedComputeCandidate[T] {
  request : ManagedFixedComputeRequest[T]
  registration : CapabilityRegistration
  duration : @cost.DurationEstimate
  quantities : QueryQuantities
}

///|
struct PreparedManagedCompute[T, P] {
  candidate : ManagedFixedComputeCandidate[T]
  payload : P
}

///|
struct ManagedFixedComputeChoice[T] {
  candidate : ManagedFixedComputeCandidate[T]
  reason : @cost.CostChoice
}

///|
pub enum ManagedFixedComputeSelection[T] {
  Proposed(ManagedFixedComputeChoice[T])
  Deferred
  NoCandidates
}

///|
/// Connector-author preparation only. It neither pins input material nor
/// authorizes execution/publication, and its physical quantities do not replace
/// the request's logical capacity checks.
pub fn[T, P] bind_managed_compute_candidate(
  registration : CapabilityRegistration,
  request : ManagedFixedComputeRequest[T],
  payload : P,
  work_slots : Int,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : QueryQuantities,
  max_entries : Int,
) -> Result[PreparedManagedCompute[T, P], FixedComputeIssue] {
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
pub fn[T, P] prepared_managed_compute_candidate(
  value : PreparedManagedCompute[T, P],
) -> ManagedFixedComputeCandidate[T] {
  value.candidate
}

///|
pub fn[T, P] managed_fixed_compute_choice_payload(
  choice : ManagedFixedComputeChoice[T],
  prepared : PreparedManagedCompute[T, P],
) -> P? {
  if prepared.candidate.registration.owner.live &&
    physical_equal(choice.candidate, prepared.candidate) {
    Some(prepared.payload)
  } else {
    None
  }
}

///|
/// Pure candidate comparison. Input availability is rechecked at execution
/// admission; comparison does not acquire material or consume a use right.
pub fn[T] choose_managed_fixed_compute_candidate(
  registry : CapabilityRegistry,
  request : ManagedFixedComputeRequest[T],
  candidates : Array[ManagedFixedComputeCandidate[T]],
  host_priority : Array[Int]?,
  max_entries : Int,
) -> Result[ManagedFixedComputeSelection[T], FixedComputeIssue] {
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
pub fn[T] managed_fixed_compute_choice_reason(
  choice : ManagedFixedComputeChoice[T],
) -> @cost.CostChoice {
  choice.reason
}

///|
pub fn[T] managed_fixed_compute_candidate_duration(
  candidate : ManagedFixedComputeCandidate[T],
) -> @cost.DurationEstimate {
  candidate.duration
}

///|
pub fn[T] managed_fixed_compute_candidate_request(
  candidate : ManagedFixedComputeCandidate[T],
) -> ManagedFixedComputeRequest[T] {
  candidate.request
}

///|
pub fn[T] managed_fixed_compute_candidate_registration(
  candidate : ManagedFixedComputeCandidate[T],
) -> CapabilityRegistration {
  candidate.registration
}

///|
pub fn[T] managed_fixed_compute_candidate_quantities(
  candidate : ManagedFixedComputeCandidate[T],
) -> QueryQuantities {
  candidate.quantities
}
