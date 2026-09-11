///|
pub(all) enum SelectedPolicyIssue {
  InvalidLimits
  ForeignEnvironment
  PolicyMismatch
  BudgetExceeded
} derive(Eq, Debug)

///|
pub(all) struct SelectedPolicyUsage {
  work : Int
  text_bytes : Int
  local_input_nodes : Int
  policy_nodes : Int
} derive(Eq, Debug)

///|
struct SelectedPolicyContext {
  context : ReconciledContexts
  capacity : @environment.Capacity
  usage : SelectedPolicyUsage
}

///|
/// Establish environment selection, not Host authorization or full admission.
pub fn bind_capacity_policy(
  context : ReconciledContexts,
  capacity : @environment.Capacity,
  max_work~ : Int,
  max_text_bytes~ : Int,
  max_policy_nodes~ : Int,
) -> Result[SelectedPolicyContext, SelectedPolicyIssue] {
  if max_work < 0 || max_text_bytes < 0 || max_policy_nodes < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(
      @environment.capacity_environment(capacity),
      @local_inputs.program_environment(context.snapshots),
    ) {
    return Err(ForeignEnvironment)
  }
  if @policy.cid(@environment.capacity_policy(capacity)) !=
    @policy.cid(context.wired.stages.policy) {
    return Err(PolicyMismatch)
  }
  let (bytes, nodes) = @environment.capacity_usage(capacity)
  let before = context.usage
  if before.work >= max_work ||
    nodes > max_work - before.work - 1 ||
    before.text_bytes > max_text_bytes ||
    bytes > max_text_bytes - before.text_bytes ||
    nodes > max_policy_nodes {
    return Err(BudgetExceeded)
  }
  Ok({
    context,
    capacity,
    usage: {
      work: before.work + nodes + 1,
      text_bytes: before.text_bytes + bytes,
      local_input_nodes: before.local_input_nodes,
      policy_nodes: nodes,
    },
  })
}

///|
pub fn policy_context(v : SelectedPolicyContext) -> ReconciledContexts {
  v.context
}

///|
pub fn selected_capacity(v : SelectedPolicyContext) -> @environment.Capacity {
  v.capacity
}

///|
pub fn selected_policy_usage(v : SelectedPolicyContext) -> SelectedPolicyUsage {
  v.usage
}
