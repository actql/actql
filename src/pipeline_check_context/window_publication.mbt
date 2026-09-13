///|
/// An owned connection to Result publication requirements, not a receipt or an
/// artifact ceiling applied to intermediate window output.
pub struct WindowPublicationResources {
  requirement_index : Int
  site : OperationRequirementSite
  membership : WindowMembershipLimit
  publications : ProgramPublicationClosure
}

///|
fn link_window_publication_resources(
  index : ProgramOperationResolutionIndex,
  publications : ProgramPublicationClosure,
  max_work : Int,
) -> Result[ProgramOperationResolutionIndex, OperationClosureIssue] {
  if !physical_equal(publications.owner.resolutions, index) {
    return Err(ForeignOccurrence(0))
  }
  let count = index.states.length()
  if index.work > max_work || count > (max_work - index.work) / 2 {
    return Err(BudgetExceeded)
  }
  let mut work = index.work + count * 2
  let states = index.states.copy()
  let mut linked = 0
  for i in 0..<count {
    let site = index.requirements.entries[i]
    guard states[i] is Unresolved &&
      site.requirement
      is @pipeline.WindowRequirement(@window.ResolvePublicationResources) else {
      continue
    }
    let start = i - site.index
    let mut selected : WindowMembershipLimit? = None
    for j in 0..<@pipeline.operation_obligations_count(site.obligations) {
      if work == max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      if index.states.get(start + j)
        is Some(Execution(WindowMembershipLimit(limit))) &&
        physical_equal(limit.site.obligations, site.obligations) &&
        physical_equal(limit.site.pipeline, site.pipeline) &&
        limit.site.stage == site.stage &&
        limit.site.step == site.step &&
        limit.site.producer_visit == site.producer_visit {
        if selected is Some(_) {
          return Err(ForeignOccurrence(i))
        }
        selected = Some(limit)
      }
    }
    guard selected is Some(membership) else {
      return Err(IncompleteResolution(i))
    }
    states[i] = Resolved(
      WindowPublication({
        requirement_index: i,
        site,
        membership,
        publications,
      }),
    )
    linked += 1
  }
  Ok({ ..index, states, unresolved: index.unresolved - linked, work, })
}
