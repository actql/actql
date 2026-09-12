///|
/// Explicit enforcement configuration for a checked fragment. Immutable and
/// reusable; every execution obtains fresh counters. Not an input-proof token.
priv struct FragmentRuntimeContext {
  fragment : CheckedFragment
  kernel : @lower.PreparedKernel
  limits : LogicalLimits
  physical : RegistryLimits
}

///|
priv enum FragmentRuntimeIssue {
  InvalidLimits
  ExceedsRequest
  KernelMismatch
  Logical(LogicalBudgetIssue)
}

///|
fn prepare_fragment_runtime_context(
  fragment : CheckedFragment,
  limits : LogicalLimits,
  physical : RegistryLimits,
) -> Result[FragmentRuntimeContext, FragmentRuntimeIssue] {
  if validate_logical_limits(limits) is Err(_) ||
    physical.max_body_bytes < 0 ||
    physical.max_body_nodes < 0 ||
    physical.max_body_depth < 0 {
    return Err(InvalidLimits)
  }
  let request = fragment.candidate.material.request.request
  let (rows, bytes) = @lower.fragment_request_ceilings(request)
  if limits.max_input_rows > rows || limits.max_value_bytes > bytes {
    return Err(ExceedsRequest)
  }
  let roots = @lower.fragment_pipeline_roots(
    @lower.fragment_request_pipeline(request),
  )
  let (start, end) = @lower.root_step_range(roots)
  if end != start + 1 {
    return Err(KernelMismatch)
  }
  guard @lower.sequence_step(@lower.root_sequence(roots), start)
    is Some(@lower.RowStep(kernel)) else {
    return Err(KernelMismatch)
  }
  Ok({ fragment, kernel, limits, physical, })
}

///|
fn fragment_runtime_for_kernel(
  context : FragmentRuntimeContext,
  kernel : @lower.PreparedKernel,
) -> Result[LogicalBudget, FragmentRuntimeIssue] {
  if !physical_equal(context.kernel, kernel) {
    return Err(KernelMismatch)
  }
  match
    logical_budget(
      context.limits,
      context.physical.max_body_bytes,
      context.physical.max_body_nodes,
      context.physical.max_body_depth,
    ) {
    Ok(budget) => Ok(budget)
    Err(issue) => Err(Logical(issue))
  }
}
