///|
/// Typed implementation payload, never inspected by the planner.
struct NumericCompute {
  plan : NumericPlan
  request : @connector.FixedComputeRequest
}

///|
/// Independent managed-profile payload. It is intentionally distinct from the
/// legacy request so the reference implementation cannot silently relabel a
/// CID-free completion or a legacy ProducerRead.
struct ManagedNumericCompute[T] {
  plan : NumericPlan
  request : @connector.ManagedFixedComputeRequest[T]
}

///|
/// The initial reference implementation can run with no identity obligation,
/// or establish only the existing canonical ordered-row identity of this exact
/// task output. Named Result and publication identities remain a separate,
/// unsupported boundary.
pub fn[T] offer_managed_numeric_compute(
  registration : @connector.CapabilityRegistration,
  request : @connector.ManagedFixedComputeRequest[T],
  max_entries : Int,
  max_name_bytes : Int,
  expressions : @lower.ExpressionLimits,
  work_slots : Int,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
) -> Result[
  @connector.PreparedManagedCompute[T, ManagedNumericCompute[T]],
  PlanIssue,
] {
  if @connector.managed_fixed_compute_request_input_count(request) != 1 {
    return Err(Unsupported)
  }
  let obligations = @connector.managed_fixed_compute_request_obligations(
    request,
  )
  let identities = @execution.managed_obligations_identities(obligations)
  for identity in identities {
    if identity.domain != @execution.OrderedRows ||
      identity.subject != @execution.TaskOutput ||
      identity.occurrence is Some(_) ||
      identity.need is @execution.UnestablishedRetained ||
      identity.need is @execution.EstablishedBy(@execution.BeforePublication) {
      return Err(Unsupported)
    }
  }
  let plan = match
    prepare_numeric_plan(
      @connector.managed_fixed_compute_request_owner(request),
      max_entries,
      max_name_bytes,
      expressions,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @connector.bind_managed_compute_candidate(
    registration,
    request,
    ManagedNumericCompute::{ plan, request, },
    work_slots,
    estimates,
    quantities,
    max_entries,
  ).map_err(issue => ManagedCandidate(issue))
}

///|
pub fn offer_numeric_compute(
  registration : @connector.CapabilityRegistration,
  request : @connector.FixedComputeRequest,
  max_entries : Int,
  max_name_bytes : Int,
  expressions : @lower.ExpressionLimits,
  work_slots : Int,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
) -> Result[@connector.PreparedCompute[NumericCompute], PlanIssue] {
  if @connector.fixed_compute_request_input_count(request) != 1 {
    return Err(Unsupported)
  }
  // This specialization does not implement shared fragment logical metering.
  // Never silently reinterpret an already-selected common fragment as Local-only.
  if @connector.fixed_compute_request_capacity(request).common_fragment
    is Some(_) {
    return Err(Candidate(CommonFragmentUnsupported))
  }
  let plan = match
    prepare_numeric_plan(
      @connector.fixed_compute_request_owner(request),
      max_entries,
      max_name_bytes,
      expressions,
    ) {
    Ok(plan) => plan
    Err(issue) => return Err(issue)
  }
  @connector.bind_compute_candidate(
    registration,
    request,
    NumericCompute::{ plan, request, },
    work_slots,
    estimates,
    quantities,
    max_entries,
  ).map_err(issue => Candidate(issue))
}
