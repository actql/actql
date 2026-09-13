///|
/// Bind the selected payload-byte ceiling separately for every analytic frame.
pub fn link_program_analytic_string_limits(
  index : ProgramOperationResolutionIndex,
  max_work : Int,
  max_links : Int,
  max_candidates : Int,
) -> Result[ProgramOperationResolutionIndex, GroupStringLimitIssue] {
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
    guard site.requirement is @pipeline.RelationRequirement(pending) &&
      pending.kind is @relation.AggregateEnvelope &&
      @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
      step.operation is @pipeline.Unary(operation) &&
      @relation.analytic(operation) is Some(analytic) &&
      @relation.analytic_call_for_validation(analytic, site.index) is Some(call) &&
      call.function is @relation.Aggregate(aggregate) &&
      @relation.aggregate_function(aggregate) is @relation.StringAgg else {
      continue
    }
    if links == max_links {
      return Err(BudgetExceeded)
    }
    guard states[i] is Unresolved &&
      step.input is Some(input) &&
      @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
      @pipeline.input_occurrence_count(step) == 1 else {
      return Err(InvalidRequirement)
    }
    let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
    if edge.role != @pipeline.Primary || edge.target != input {
      return Err(InvalidRequirement)
    }
    let stages = index.requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
    let policy = @capacity.application_closure_policy(
      stages.contexts[site.stage].context.capacity,
    )
    if @relation.aggregate_byte_limit(aggregate) is None &&
      @policy.ceiling(policy, "max_aggregate_string_bytes") is None {
      // No independent payload guard was selected. The separate mandatory
      // analytic wire envelope still bounds output; do not invent a raw cap.
      states[i] = Execution(
        AnalyticExecution({
          site,
          step,
          input,
          operation,
          analytic,
          rule: ValidateResultContract(call),
        }),
      )
      links += 1
      continue
    }
    if candidates == max_candidates {
      return Err(BudgetExceeded)
    }
    let limit = match
      select_analytic_string_limit(
        index,
        i,
        index.work + (max_work - work),
        max_candidates - candidates,
      ) {
      Ok(limit) => limit
      Err(issue) => return Err(issue)
    }
    work += limit.work - index.work
    if limit.host is Some(_) {
      candidates += 1
    }
    if limit.guard_value is Some(_) {
      candidates += 1
    }
    states[i] = Execution(
      AnalyticExecution({
        site,
        step,
        input,
        operation,
        analytic,
        rule: EnforceStringBytes(call, limit),
      }),
    )
    links += 1
  }
  Ok({ ..index, states, unresolved: index.unresolved - links, work, })
}
