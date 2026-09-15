///|
pub struct WindowMembershipLimit {
  site : OperationRequirementSite
  bounds : WindowMembershipBounds
  policy : @policy.Policy
  host : @policy.Ceiling
  maximum : Int64
}

///|
/// Select an output enforcement bound; unknown input cardinality stays unknown.
/// Resource publication and persistent witness construction remain separate.
pub fn link_program_window_membership_limits(
  index : ProgramOperationResolutionIndex,
  max_work : Int,
  max_links : Int,
  max_candidates : Int,
) -> Result[ProgramOperationResolutionIndex, WindowMembershipBoundIssue] {
  if max_work < 0 || max_links < 0 || max_candidates < 0 {
    return Err(InvalidLimits)
  }
  let count = index.states.length()
  if index.work > max_work || count > (max_work - index.work) / 2 {
    return Err(BudgetExceeded)
  }
  let mut work = index.work + count * 2
  let states = index.states.copy()
  let mut links = 0
  let mut candidates = 0
  let stages = index.requirements.stages
  for i in 0..<count {
    let site = index.requirements.entries[i]
    guard site.requirement
      is @pipeline.WindowRequirement(@window.ResolveMembershipBound) else {
      continue
    }
    if links == max_links || candidates == max_candidates {
      return Err(BudgetExceeded)
    }
    guard states[i] is Unresolved else { return Err(ForeignEvidence) }
    let bounds = match
      collect_window_membership_bounds(
        index,
        i,
        index.work + (max_work - work),
        max_candidates - candidates - 1,
      ) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    work += bounds.work - index.work
    candidates += bounds.candidates.length() + 1
    let policy = @capacity.application_closure_policy(
      stages.contexts[site.stage].context.capacity,
    )
    let field = match @window.input(bounds.execution.window) {
      @carrier.Relation(_) => "max_relation_output_rows"
      @carrier.EventValue(_) => "max_temporal_output_rows"
      _ => return Err(ForeignEvidence)
    }
    guard @policy.ceiling(policy, field) is Some(host) else {
      return Err(ForeignEvidence)
    }
    let maximum = match bounds.maximum {
      Some(n) => Int64::min(n, @policy.ceiling_value(host))
      None => @policy.ceiling_value(host)
    }
    states[i] = Execution(
      WindowMembershipLimit({ site, bounds, policy, host, maximum, }),
    )
    links += 1
  }
  Ok({ ..index, states, unresolved: index.unresolved - links, work, })
}
