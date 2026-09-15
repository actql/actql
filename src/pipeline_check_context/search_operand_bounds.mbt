///|
priv enum SearchOperandIssue {
  BudgetExceeded
  ForeignEvidence
}

///|
priv struct SearchOperandBounds {
  closure : @capacity.ApplicationClosure
  candidates : Array[Array[@capacity.TargetMembership]]
  selected : Array[@step_bounds.TargetRows?]
  work : Int
}

///|
/// Scan original claim slots across producer visits, charging holes and misses.
/// Keep memberships for every applicable proof without multiplying alternatives.
fn collect_search_operand_bounds(
  owner : ProgramOperationResolutionIndex,
  site : OperationRequirementSite,
  left : @pipeline.Target,
  right : @pipeline.Target,
  initial_work : Int,
  max_work : Int,
  max_candidates : Int,
) -> Result[SearchOperandBounds, SearchOperandIssue] {
  let mut work = initial_work
  let spend = fn() -> Bool {
    if work >= max_work {
      return false
    }
    work += 1
    true
  }
  let stages = owner.requirements.stages
  let closure = stages.contexts[site.stage].context.capacity
  let candidates : Array[Array[@capacity.TargetMembership]] = [[], []]
  let selected : Array[@step_bounds.TargetRows?] = [None, None]
  let mut count = 0
  for
    visit in 0..<@pipeline.contextual_closure_count(
      @capacity.application_closure_orders(closure),
    ) {
    guard spend() else { return Err(BudgetExceeded) }
    let source = @capacity.application_coverage_sources(
      @capacity.application_closure_at(closure, visit).unwrap(),
    )
    let applications = @capacity.source_coverage_program(source)
    let arithmetic = @wire.program_claim_arithmetic(
      @step_bounds.application_claims(applications),
    )
    for claim in 0..<@wire.claim_count(arithmetic) {
      guard spend() else { return Err(BudgetExceeded) }
      guard @step_bounds.application_at(applications, claim) is Some(bound) else {
        continue
      }
      for side in 0..<2 {
        guard spend() else { return Err(BudgetExceeded) }
        let (result, used) = @step_bounds.check_target_rows_usage(
          site.pipeline,
          if side == 0 {
            left
          } else {
            right
          },
          bound,
          max_work - work,
        )
        work += used
        match result {
          Ok(rows) => {
            if count == max_candidates {
              return Err(BudgetExceeded)
            }
            let membership = match
              @capacity.bind_producer_target_membership(
                closure,
                rows,
                site.producer_visit,
                visit,
                claim,
              ) {
              Ok(v) => v
              Err(_) => return Err(ForeignEvidence)
            }
            candidates[side].push(membership)
            count += 1
            if selected[side] is None ||
              @step_bounds.target_rows_value(rows) <
              @step_bounds.target_rows_value(selected[side].unwrap()) {
              selected[side] = Some(rows)
            }
          }
          Err(
            @step_bounds.WrongUnit
            | @step_bounds.UnrelatedBound
            | @step_bounds.MissingProducer
          ) => ()
          Err(@step_bounds.WorkLimit) => return Err(BudgetExceeded)
          Err(_) => return Err(ForeignEvidence)
        }
      }
    }
  }
  Ok({ closure, candidates, selected, work, })
}
