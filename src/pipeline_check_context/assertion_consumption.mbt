///|
pub struct AssertionConsumptionLink {
  requirement_index : Int
  site : OperationRequirementSite
  results : @results.CheckedResults
}

///|
// Traverse from declared stage Results, not from arbitrary later references.
// All input occurrences count, including right operands and shared branches.
fn assertion_consumption_links(
  requirements : ProgramOperationRequirements,
  max_work : Int,
) -> Result[
  (Array[AssertionConsumptionLink], Int),
  OperationResolutionIndexIssue,
] {
  let stages = requirements.stages
  let mut work = 0
  let charge = fn() -> Bool {
    if work >= max_work {
      return false
    }
    work += 1
    true
  }
  let links = []
  for context in stages.contexts {
    guard charge() else { return Err(BudgetExceeded) }
    let results = context.context.results
    let pipeline = @results.pipeline(results)
    let reachable : Map[Int, Bool] = Map([])
    let pending : Array[@pipeline.Target] = []
    for i in 0..<@results.count(results) {
      guard charge() else { return Err(BudgetExceeded) }
      pending.push(@results.target(@results.result_at(results, i).unwrap()))
    }
    while pending.pop() is Some(target) {
      guard charge() else { return Err(BudgetExceeded) }
      guard target is @pipeline.Step(index) else { continue }
      if reachable.contains(index) {
        continue
      }
      reachable[index] = true
      guard @pipeline.step_at(pipeline, index) is Some(step) else {
        return Err(ForeignOccurrence(index))
      }
      for edge in 0..<@pipeline.input_occurrence_count(step) {
        guard charge() else { return Err(BudgetExceeded) }
        pending.push(@pipeline.input_occurrence_at(step, edge).unwrap().target)
      }
    }
    for i in 0..<requirements.entries.length() {
      guard charge() else { return Err(BudgetExceeded) }
      let site = requirements.entries[i]
      if physical_equal(site.pipeline, pipeline) &&
        reachable.contains(site.step) {
        if site.requirement is @pipeline.RelationRequirement(pending) &&
          pending.kind is @relation.AssertionConsumption {
          links.push({ requirement_index: i, site, results, })
        }
      }
    }
  }
  Ok((links, work))
}
