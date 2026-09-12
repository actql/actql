///|
pub(all) enum SelectedPolicyIssue {
  InvalidLimits
  ForeignEnvironment
  PolicyMismatch
  LookupExecution(@environment.LookupExecutionIssueKind)
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
  lookup : @environment.LookupExecution
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
  let lookup = match
    @environment.check_lookup_execution(
      @environment.capacity_environment(capacity),
      {
        max_work: max_work - before.work - nodes - 1,
        max_bytes: max_text_bytes - before.text_bytes - bytes,
      },
    ) {
    Ok(v) => v
    Err(e) =>
      match e.kind {
        @environment.WorkLimit | @environment.ByteLimit =>
          return Err(BudgetExceeded)
        _ => return Err(LookupExecution(e.kind))
      }
  }
  let (lookup_work, lookup_bytes) = @environment.lookup_execution_usage(lookup)
  let lookup_nodes = if @environment.lookup_execution_policy(lookup) is Some(_) {
    8
  } else {
    0
  }
  if lookup_nodes > max_policy_nodes - nodes {
    return Err(BudgetExceeded)
  }
  Ok({
    context,
    capacity,
    lookup,
    usage: {
      work: before.work + nodes + 1 + lookup_work,
      text_bytes: before.text_bytes + bytes + lookup_bytes,
      local_input_nodes: before.local_input_nodes,
      policy_nodes: nodes + lookup_nodes,
    },
  })
}

///|
pub fn selected_lookup_execution(
  v : SelectedPolicyContext,
) -> @environment.LookupExecution {
  v.lookup
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
