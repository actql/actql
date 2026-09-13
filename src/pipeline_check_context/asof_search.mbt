///|
pub enum AsOfSearchLimitIssue {
  InvalidLimits
  InvalidRequirement
  ForeignEvidence
  BudgetExceeded
  MissingSearchBound
  Overflow
}

///|
struct AsOfSearchBounds {
  owner : ProgramOperationResolutionIndex
  requirement : Int
  closure : @capacity.ApplicationClosure
  candidates : Array[Array[@capacity.TargetMembership]]
  product : @step_bounds.AsOfSearchProduct?
  work : Int
}

///|
/// Keep all candidate memberships, but multiply only the minimum for each side.
/// No cross product of proof alternatives and no substitution of Host row caps.
pub fn collect_asof_search_bounds(
  owner : ProgramOperationResolutionIndex,
  requirement : Int,
  max_work : Int,
  max_candidates : Int,
) -> Result[AsOfSearchBounds, AsOfSearchLimitIssue] {
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
    site.requirement is @pipeline.AsOfRequirement(ResolveSearchWork) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.AsOfJoin(right~, ..) &&
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
  let result = @step_bounds.check_asof_search_product(
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
pub struct AsOfSearchCheck {
  site : OperationRequirementSite
  bounds : AsOfSearchBounds
  product : @step_bounds.AsOfSearchProduct
}

///|
/// Binds the single-visit ceiling; completed conformance is still a runtime duty.
pub fn link_program_asof_search_limits(
  index : ProgramOperationResolutionIndex,
  max_work : Int,
  max_links : Int,
  max_candidates : Int,
) -> Result[ProgramOperationResolutionIndex, AsOfSearchLimitIssue] {
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
    guard site.requirement is @pipeline.AsOfRequirement(ResolveSearchWork) else {
      continue
    }
    if links == max_links {
      return Err(BudgetExceeded)
    }
    guard states[i] is Unresolved else { return Err(ForeignEvidence) }
    let bounds = match
      collect_asof_search_bounds(
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
    states[i] = Execution(AsOfSearch({ site, bounds, product, }))
    links += 1
  }
  Ok({ ..index, states, unresolved: index.unresolved - links, work, })
}

///|
pub fn asof_search_bound_owner(
  v : AsOfSearchBounds,
) -> ProgramOperationResolutionIndex {
  v.owner
}

///|
pub fn asof_search_bound_closure(
  v : AsOfSearchBounds,
) -> @capacity.ApplicationClosure {
  v.closure
}

///|
pub fn asof_search_bound_requirement(v : AsOfSearchBounds) -> Int {
  v.requirement
}

///|
pub fn asof_search_bound_product(
  v : AsOfSearchBounds,
) -> @step_bounds.AsOfSearchProduct? {
  v.product
}

///|
pub fn asof_search_bound_candidate_count(
  v : AsOfSearchBounds,
  side : Int,
) -> Int {
  v.candidates.get(side).map(a => a.length()).unwrap_or(0)
}

///|
pub fn asof_search_bound_candidate_at(
  v : AsOfSearchBounds,
  side : Int,
  index : Int,
) -> @capacity.TargetMembership? {
  v.candidates.get(side).bind(a => a.get(index))
}

///|
pub fn asof_search_bound_work(v : AsOfSearchBounds) -> Int {
  v.work
}
