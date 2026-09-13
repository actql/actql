///|
/// Bind ordinary array aggregate limits to atomic output enforcement. Other
/// aggregate envelopes and numeric observations remain unresolved.
pub fn link_program_group_array_limits(
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
  // Charge the copy and every inventory slot before allocating the new states.
  let mut work = index.work + count * 2
  let states = index.states.copy()
  let mut links = 0
  let mut candidates = 0
  for i in 0..<count {
    let site = index.requirements.entries[i]
    guard site.requirement is @pipeline.RelationRequirement(pending) &&
      pending.kind is @relation.AggregateEnvelope else {
      continue
    }
    guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
      step.operation is @pipeline.Unary(operation) &&
      @relation.operation(operation) == @relation.Group &&
      @relation.group(operation) is Some(group) &&
      @relation.aggregate_for_validation(group, site.index) is Some(call) &&
      @relation.aggregate_function(call) is @relation.ArrayAgg else {
      continue
    }
    if links == max_links || candidates == max_candidates {
      return Err(BudgetExceeded)
    }
    guard states[i] is Unresolved &&
      step.input is Some(input) &&
      @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
      @pipeline.input_occurrence_count(step) == 1 else {
      return Err(ForeignEvidence)
    }
    let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
    if edge.role != @pipeline.Primary || edge.target != input {
      return Err(ForeignEvidence)
    }
    let limit = match
      select_group_array_limit(
        index,
        i,
        index.work + (max_work - work),
        max_candidates - candidates,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    work += limit.work - index.work
    candidates += 1 + limit.candidates.length()
    if limit.guard_value is Some(_) {
      candidates += 1
    }
    states[i] = Execution(
      GroupExecution({
        site,
        step,
        input,
        operation,
        group,
        rule: EnforceArrayItems(limit),
      }),
    )
    links += 1
  }
  Ok({ ..index, states, unresolved: index.unresolved - links, work, })
}
