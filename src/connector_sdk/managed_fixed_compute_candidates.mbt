///|
/// Managed-profile candidate with the same registration and cost semantics as
/// legacy fixed Compute, but an explicitly different input contract.
struct ManagedFixedComputeCandidate[T] {
  request : ManagedFixedComputeRequest[T]
  registration : CapabilityRegistration
  duration : @cost.DurationEstimate
  quantities : QueryQuantities
  numeric_reductions : Array[NumericReductionSupport]
}

///|
/// One implementation-declared profile member. This is capability metadata,
/// not profile admission, selection authority, or capture evidence.
struct NumericReductionSupport {
  profile_cid : String
  member_cid : String
}

///|
fn valid_content_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < value.length(); index = index + 1 {
    let code = value[index].to_int()
    if !((code >= 48 && code <= 57) || (code >= 97 && code <= 102)) {
      return false
    }
  }
  true
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
  numeric_reductions? : Array[NumericReductionSupport] = [],
) -> Result[PreparedManagedCompute[T, P], FixedComputeIssue] {
  if max_entries < 0 {
    return Err(InvalidLimits)
  }
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
  let reductions = match
    checked_numeric_reduction_supports(numeric_reductions, max_entries) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    @cost.assess_serial(
      work_slots,
      estimates,
      max_entries - reductions.length(),
    ) {
    Err(issue) => Err(Cost(issue))
    Ok(duration) =>
      Ok({
        candidate: {
          request,
          registration,
          duration,
          quantities,
          numeric_reductions: reductions,
        },
        payload,
      })
  }
}

///|
/// Candidate metadata is copied and validated before either execution form
/// may use it to select a task-owned numeric reduction.
fn checked_numeric_reduction_supports(
  declarations : Array[NumericReductionSupport],
  max_entries : Int,
) -> Result[Array[NumericReductionSupport], FixedComputeIssue] {
  if declarations.length() > max_entries {
    return Err(PlanningLimit)
  }
  let reductions = declarations.copy()
  for index, reduction in reductions {
    if !valid_content_cid(reduction.profile_cid) ||
      !valid_content_cid(reduction.member_cid) {
      return Err(InvalidLimits)
    }
    for prior in 0..<index {
      if reductions[prior].profile_cid == reduction.profile_cid {
        return Err(InvalidLimits)
      }
    }
  }
  Ok(reductions)
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
  let effective_priority = match host_priority {
    Some(order) => Some(order)
    None => {
      let positions = Array::makei(candidates.length(), index => index)
      positions.sort_by((left, right) => {
        capability_registration_selection_key(candidates[left].registration).compare(
          capability_registration_selection_key(candidates[right].registration),
        )
      })
      Some(positions)
    }
  }
  @cost.choose_serial(
    durations,
    effective_priority,
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

///|
pub fn numeric_reduction_support(
  profile_cid : String,
  member_cid : String,
) -> Result[NumericReductionSupport, FixedComputeIssue] {
  if !valid_content_cid(profile_cid) || !valid_content_cid(member_cid) {
    Err(InvalidLimits)
  } else {
    Ok({ profile_cid, member_cid, })
  }
}

///|
pub fn[T] managed_fixed_compute_candidate_numeric_reduction_count(
  candidate : ManagedFixedComputeCandidate[T],
) -> Int {
  candidate.numeric_reductions.length()
}

///|
pub fn[T] managed_fixed_compute_candidate_numeric_reduction_at(
  candidate : ManagedFixedComputeCandidate[T],
  index : Int,
) -> NumericReductionSupport? {
  candidate.numeric_reductions.get(index)
}

///|
pub fn numeric_reduction_support_profile_cid(
  support : NumericReductionSupport,
) -> String {
  support.profile_cid
}

///|
pub fn numeric_reduction_support_member_cid(
  support : NumericReductionSupport,
) -> String {
  support.member_cid
}
