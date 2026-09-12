///|
pub(all) enum SourcePolicyIssue {
  InvalidLimits
  ForeignContext
  BudgetExceeded
} derive(Eq, Debug)

///|
struct SourcePolicyContext {
  rows : SourceRowContexts
  policy : SelectedPolicyContext
  work : Int
}

///|
/// Join the two checked branches at their exact common Program input owner.
/// An absent lookup component stays absent; this is not acquisition admission.
pub fn bind_source_policy(
  rows : SourceRowContexts,
  policy : SelectedPolicyContext,
  max_work : Int,
) -> Result[SourcePolicyContext, SourcePolicyIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(rows.requests.inputs, policy.context) {
    return Err(ForeignContext)
  }
  // Both branches already count this exact immutable input preparation.
  let added = policy.usage.work - policy.context.usage.work
  if rows.work >= max_work || added > max_work - rows.work - 1 {
    return Err(BudgetExceeded)
  }
  Ok({ rows, policy, work: rows.work + added + 1, })
}

///|
pub fn source_policy_rows(v : SourcePolicyContext) -> SourceRowContexts {
  v.rows
}

///|
pub fn source_policy_selected(v : SourcePolicyContext) -> SelectedPolicyContext {
  v.policy
}

///|
pub fn source_policy_work(v : SourcePolicyContext) -> Int {
  v.work
}
