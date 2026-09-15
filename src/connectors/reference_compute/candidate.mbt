///|
/// Typed implementation payload, never inspected by the planner.
struct NumericCompute {
  plan : NumericPlan
  request : @connector.FixedComputeRequest
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
    { plan, request, },
    work_slots,
    estimates,
    quantities,
    max_entries,
  ).map_err(issue => Candidate(issue))
}
