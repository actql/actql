///|
/// Resolve every nest item requirement atomically. Enforcement limits arrays;
/// it never truncates children or substitutes for recursive output admission.
pub fn link_program_nest_item_limits(
  index : ProgramOperationResolutionIndex,
  max_work : Int,
  max_links : Int,
  max_candidates : Int,
) -> Result[ProgramOperationResolutionIndex, GroupArrayLimitIssue] {
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
  for i in 0..<count {
    guard index.requirements.entries[i].requirement
      is @pipeline.NestRequirement(ResolveItemLimit) else {
      continue
    }
    if links == max_links || candidates == max_candidates {
      return Err(BudgetExceeded)
    }
    guard states[i] is Unresolved else { return Err(ForeignEvidence) }
    let limit = match
      select_nest_item_limit(
        index,
        i,
        index.work + (max_work - work),
        max_candidates - candidates,
      ) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    work += limit.work - index.work
    candidates += 1 + limit.candidates.length()
    if limit.guard_value is Some(_) {
      candidates += 1
    }
    states[i] = Execution(NestItems(limit))
    links += 1
  }
  Ok({ ..index, states, unresolved: index.unresolved - links, work, })
}

///|
/// Per-parent array ceiling. Child-total evidence can bound each array without
/// proving parent-key uniqueness; it does not bound total repeated payload size.
pub struct NestItemLimit {
  owner : ProgramOperationResolutionIndex
  requirement : Int
  site : OperationRequirementSite
  operation : @nest.CheckedNest
  parent : @pipeline.Target
  child : @pipeline.Target
  host : @policy.Ceiling
  guard_value : Int64?
  guard_resolution : OperationScalarResolution?
  maximum : Int64
  priv candidates : Array[@capacity.TargetMembership]
  work : Int
}

///|
pub fn nest_item_candidate_count(value : NestItemLimit) -> Int {
  value.candidates.length()
}

///|
pub fn nest_item_candidate_at(
  value : NestItemLimit,
  index : Int,
) -> @capacity.TargetMembership? {
  value.candidates.get(index)
}

///|
pub fn select_nest_item_limit(
  owner : ProgramOperationResolutionIndex,
  requirement : Int,
  max_work : Int,
  max_candidates : Int,
) -> Result[NestItemLimit, GroupArrayLimitIssue] {
  if max_work < 0 || max_candidates < 1 {
    return Err(InvalidLimits)
  }
  if owner.work >= max_work {
    return Err(BudgetExceeded)
  }
  let mut work = owner.work + 1
  guard owner.requirements.entries.get(requirement) is Some(site) &&
    site.requirement is @pipeline.NestRequirement(ResolveItemLimit) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Nest(right=child, checked=operation) &&
    step.input is Some(parent) &&
    @nest.pending_validation_at(operation, site.index) ==
    Some(@nest.ResolveItemLimit) &&
    @pipeline.input_occurrence_count(step) == 2 else {
    return Err(InvalidRequirement)
  }
  let left = @pipeline.input_occurrence_at(step, 0).unwrap()
  let right = @pipeline.input_occurrence_at(step, 1).unwrap()
  if left.role != @pipeline.Left ||
    left.target != parent ||
    right.role != @pipeline.Right ||
    right.target != child {
    return Err(ForeignEvidence)
  }
  let stages = owner.requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
  let closure = stages.contexts[site.stage].context.capacity
  let policy = @capacity.application_closure_policy(closure)
  guard @policy.ceiling(policy, "max_aggregate_array_items") is Some(host) else {
    return Err(MissingHostCeiling)
  }
  let mut guard_value = None
  let mut guard_resolution = None
  match @nest.item_guard(operation) {
    Some(@nest.Literal(value)) => guard_value = Some(value)
    Some(@nest.Parameter(name)) => {
      // The inventory retains every obligation of a group contiguously. Read
      // its already-indexed scalar state instead of rescanning all parameters
      // for every nest operation or importing a content-equivalent binding.
      if requirement < site.index {
        return Err(ForeignEvidence)
      }
      let base = requirement - site.index
      for local_index in 0..<@nest.pending_validation_count(operation) {
        if work >= max_work {
          return Err(BudgetExceeded)
        }
        work += 1
        guard @nest.pending_validation_at(operation, local_index)
          is Some(@nest.BindGuard(bound_name)) else {
          continue
        }
        if local_index >= owner.states.length() - base {
          return Err(ForeignEvidence)
        }
        let position = base + local_index
        guard owner.states[position] is Resolved(Scalar(resolution)) else {
          return Err(UnresolvedGuard)
        }
        let other = resolution.site
        if resolution.requirement_index != position ||
          !physical_equal(owner.requirements.entries[position], other) ||
          other.index != local_index ||
          other.stage != site.stage ||
          other.producer_visit != site.producer_visit ||
          other.step != site.step ||
          other.group != site.group ||
          !physical_equal(other.pipeline, site.pipeline) {
          return Err(ForeignEvidence)
        }
        let cost = Int::min(name.length(), bound_name.length()) + 1
        if cost > max_work - work {
          return Err(BudgetExceeded)
        }
        work += cost
        if name != bound_name {
          continue
        }
        guard @nest.pending_validation_at(operation, other.index) ==
          Some(@nest.BindGuard(name)) &&
          resolution.value is Integer(value) &&
          value > 0L else {
          return Err(UnresolvedGuard)
        }
        if guard_resolution is Some(_) {
          return Err(ForeignEvidence)
        }
        guard_value = Some(value)
        guard_resolution = Some(resolution)
      }
      if guard_value is None {
        return Err(UnresolvedGuard)
      }
    }
    None => ()
  }
  let count = if guard_value is Some(_) { 2 } else { 1 }
  if count > max_candidates {
    return Err(BudgetExceeded)
  }
  let (candidates, used) = match
    collect_target_row_candidates(
      closure,
      site.pipeline,
      child,
      Some(site.producer_visit),
      max_work - work,
      max_candidates - count,
    ) {
    Ok(found) => found
    Err(CandidateBudget) => return Err(BudgetExceeded)
    Err(_) => return Err(ForeignEvidence)
  }
  work += used
  let mut maximum = @policy.ceiling_value(host)
  if guard_value is Some(value) {
    maximum = Int64::min(maximum, value)
  }
  for candidate in candidates {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    maximum = Int64::min(
      maximum,
      @step_bounds.target_rows_value(
        @capacity.target_membership_rows(candidate),
      ),
    )
  }
  Ok({
    owner,
    requirement,
    site,
    operation,
    parent,
    child,
    host,
    guard_value,
    guard_resolution,
    maximum,
    candidates,
    work,
  })
}
