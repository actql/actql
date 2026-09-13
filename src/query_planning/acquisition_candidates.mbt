///|
/// Typed provider payload retained outside the common comparison interface.
/// Only this exact preparation can resolve a proposed choice to its payload.
struct PreparedAcquisition[T] {
  candidate : AcquisitionCandidate
  payload : T
}

///|
struct AcquisitionCandidate {
  requirement : QueryRequirement
  registration : CapabilityRegistration
  duration : @cost.DurationEstimate
  quantities : QueryQuantities
}

///|
struct AcquisitionChoice {
  candidate : AcquisitionCandidate
  reason : @cost.CostChoice
}

///|
pub enum AcquisitionSelection {
  Proposed(AcquisitionChoice)
  Deferred
  NoCandidates
}

///|
fn[T] bind_acquisition_candidate(
  registration : CapabilityRegistration,
  requirement : QueryRequirement,
  payload : T,
  duration : @cost.DurationEstimate,
  quantities : QueryQuantities,
) -> Result[PreparedAcquisition[T], QueryPlanningIssue] {
  if !registration.owner.live {
    return Err(CapabilityClosed)
  }
  if !registration.description.acquisition {
    return Err(AcquisitionUnsupported)
  }
  Ok({
    candidate: { requirement, registration, duration, quantities, },
    payload,
  })
}

///|
pub fn[T] prepared_acquisition_candidate(
  prepared : PreparedAcquisition[T],
) -> AcquisitionCandidate {
  prepared.candidate
}

///|
/// Typed dispatch recovery, not I/O authority. Equal payloads or registrations
/// cannot substitute for the exact candidate selected by the common planner.
pub fn[T] acquisition_choice_payload(
  choice : AcquisitionChoice,
  prepared : PreparedAcquisition[T],
) -> T? {
  if prepared.candidate.registration.owner.live &&
    physical_equal(choice.candidate, prepared.candidate) {
    Some(prepared.payload)
  } else {
    None
  }
}

///|
/// Cost proposal only: source authorization, execution, retention and capture
/// remain pending. No I/O or fallback is performed. All candidates belong to
/// the exact same requirement, not just an equal canonical CID.
pub fn choose_acquisition_candidate(
  registry : CapabilityRegistry,
  requirement : QueryRequirement,
  candidates : Array[AcquisitionCandidate],
  host_priority : Array[Int]?,
  max_entries : Int,
) -> Result[AcquisitionSelection, QueryPlanningIssue] {
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
  if candidates.length() > max_entries {
    return Err(PlanningLimit)
  }
  let durations = []
  for i in 0..<candidates.length() {
    if !physical_equal(candidates[i].requirement, requirement) {
      return Err(ForeignQuery(i))
    }
    if !capability_registration_matches(candidates[i].registration, registry) {
      return Err(ForeignCapability(i))
    }
    durations.push(candidates[i].duration)
  }
  @cost.choose_serial(
    durations,
    host_priority,
    max_entries - candidates.length(),
  )
  .map_err(issue => Cost(issue))
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
pub fn acquisition_choice_candidate(
  choice : AcquisitionChoice,
) -> AcquisitionCandidate {
  choice.candidate
}

///|
pub fn acquisition_choice_reason(
  choice : AcquisitionChoice,
) -> @cost.CostChoice {
  choice.reason
}

///|
pub fn acquisition_candidate_registration(
  candidate : AcquisitionCandidate,
) -> CapabilityRegistration {
  candidate.registration
}

///|
pub fn acquisition_candidate_duration(
  candidate : AcquisitionCandidate,
) -> @cost.DurationEstimate {
  candidate.duration
}

///|
pub fn acquisition_candidate_quantities(
  candidate : AcquisitionCandidate,
) -> QueryQuantities {
  candidate.quantities
}
