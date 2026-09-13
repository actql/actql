///|
pub enum IntervalSearchLimitIssue {
  InvalidLimits
  InvalidRequirement
  ForeignEvidence
  BudgetExceeded
  MissingSearchBound
  Overflow
}

///|
struct IntervalSearchBounds {
  owner : ProgramOperationResolutionIndex
  requirement : Int
  closure : @capacity.ApplicationClosure
  candidates : Array[Array[@capacity.TargetMembership]]
  product : @step_bounds.IntervalSearchProduct?
  work : Int
}

///|
/// Keep all candidate memberships, but multiply only the minimum for each side.
/// No cross product of proof alternatives and no substitution of Host row caps.
pub fn collect_interval_search_bounds(
  owner : ProgramOperationResolutionIndex,
  requirement : Int,
  max_work : Int,
  max_candidates : Int,
) -> Result[IntervalSearchBounds, IntervalSearchLimitIssue] {
  if max_work < 0 || max_candidates < 0 {
    return Err(InvalidLimits)
  }
  let mut work = owner.work
  let spend = fn() -> Bool {
    if work >= max_work {
      return false
    }
    work += 1
    true
  }
  guard spend() else { return Err(BudgetExceeded) }
  guard owner.requirements.entries.get(requirement) is Some(site) &&
    site.requirement is @pipeline.IntervalJoinRequirement(ResolveProductBound) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.IntervalJoin(right~, ..) &&
    step.input is Some(left) else {
    return Err(InvalidRequirement)
  }
  let operands = match
    collect_search_operand_bounds(
      owner, site, left, right, work, max_work, max_candidates,
    ) {
    Ok(v) => v
    Err(BudgetExceeded) => return Err(BudgetExceeded)
    Err(ForeignEvidence) => return Err(ForeignEvidence)
  }
  work = operands.work
  let closure = operands.closure
  let candidates = operands.candidates
  let selected = operands.selected
  if max_work - work < 3 {
    return Err(BudgetExceeded)
  }
  let result = @step_bounds.check_interval_search_product(
    site.pipeline,
    site.step,
    selected[0],
    selected[1],
    3,
  )
  work += 3
  let product = match result {
    Ok(v) => Some(v)
    Err(@step_bounds.MissingOperandBound) => None
    Err(@step_bounds.Overflow) => return Err(Overflow)
    Err(_) => return Err(ForeignEvidence)
  }
  Ok({ owner, requirement, closure, candidates, product, work, })
}

///|
pub(all) enum IntervalSearchRule {
  CheckOperandProduct
  EnforceSingleVisitSearch
} derive(Eq, Debug)

///|
/// Future enforcement, not completed matching. The realization must honor the
/// pinned single-visit condition; input validation and output caps remain separate.
pub struct IntervalSearchCheck {
  site : OperationRequirementSite
  bounds : IntervalSearchBounds
  product : @step_bounds.IntervalSearchProduct
  rule : IntervalSearchRule
}

///|
pub fn link_program_interval_search_limits(
  index : ProgramOperationResolutionIndex,
  max_work : Int,
  max_links : Int,
  max_candidates : Int,
) -> Result[ProgramOperationResolutionIndex, IntervalSearchLimitIssue] {
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
    let site = index.requirements.entries[i]
    guard site.requirement
      is @pipeline.IntervalJoinRequirement(ResolveProductBound) else {
      continue
    }
    if max_links - links < 2 {
      return Err(BudgetExceeded)
    }
    let bounds = match
      collect_interval_search_bounds(
        index,
        i,
        index.work + (max_work - work),
        max_candidates - candidates,
      ) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    work += bounds.work - index.work
    candidates += bounds.candidates[0].length() + bounds.candidates[1].length()
    guard bounds.product is Some(product) else {
      return Err(MissingSearchBound)
    }
    let start = i - site.index
    let mut matched = 0
    for slot in 0..<@pipeline.operation_obligations_count(site.obligations) {
      if work == max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      let j = start + slot
      guard index.requirements.entries.get(j) is Some(target) &&
        target.stage == site.stage &&
        target.producer_visit == site.producer_visit &&
        target.step == site.step &&
        physical_equal(target.obligations, site.obligations) else {
        return Err(ForeignEvidence)
      }
      let rule = match target.requirement {
        @pipeline.IntervalJoinRequirement(ResolveProductBound) =>
          CheckOperandProduct
        @pipeline.IntervalJoinRequirement(ResolveSearchWork) =>
          EnforceSingleVisitSearch
        _ => continue
      }
      guard states[j] is Unresolved else { return Err(ForeignEvidence) }
      states[j] = Execution(
        IntervalSearch({ site: target, bounds, product, rule, }),
      )
      matched += 1
    }
    if matched != 2 {
      return Err(ForeignEvidence)
    }
    links += matched
  }
  Ok({ ..index, states, unresolved: index.unresolved - links, work, })
}

///|
pub fn interval_search_bound_owner(
  v : IntervalSearchBounds,
) -> ProgramOperationResolutionIndex {
  v.owner
}

///|
pub fn interval_search_bound_closure(
  v : IntervalSearchBounds,
) -> @capacity.ApplicationClosure {
  v.closure
}

///|
pub fn interval_search_bound_requirement(v : IntervalSearchBounds) -> Int {
  v.requirement
}

///|
pub fn interval_search_bound_product(
  v : IntervalSearchBounds,
) -> @step_bounds.IntervalSearchProduct? {
  v.product
}

///|
pub fn interval_search_bound_candidate_count(
  v : IntervalSearchBounds,
  side : Int,
) -> Int {
  v.candidates.get(side).map(a => a.length()).unwrap_or(0)
}

///|
pub fn interval_search_bound_candidate_at(
  v : IntervalSearchBounds,
  side : Int,
  index : Int,
) -> @capacity.TargetMembership? {
  v.candidates.get(side).bind(a => a.get(index))
}

///|
pub fn interval_search_bound_work(v : IntervalSearchBounds) -> Int {
  v.work
}
