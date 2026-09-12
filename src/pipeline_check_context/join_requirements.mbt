///|
/// The inspected cardinality choice, retaining conditional key evidence and any
/// assertion separately. None is unproven, not an inferred many-to-many claim.
pub struct JoinCardinalitySelection {
  requirement_index : Int
  site : OperationRequirementSite
  evidence : @pipeline.JoinEvidence
}

///|
pub struct JoinOutputCheck {
  site : OperationRequirementSite
  capacity : @capacity.ApplicationClosure
  limit : @step_bounds.JoinLimit
}

///|
/// Enforce the checked join kind's occurrence order. Optional logical witnesses
/// are dependencies, not proof supplied by physical input enumeration.
pub struct JoinRowOrderCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  left_order : @pipeline.LogicalOrder?
  right_order : @pipeline.LogicalOrder?
  output_order : @pipeline.LogicalOrder?
}

///|
pub(all) enum JoinRequirementIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOccurrence(Int)
  MissingEvidence(Int)
  MissingCapacity(Int)
} derive(Eq, Debug)

///|
/// Consume cached evidence and the selected producer's capacity applications.
/// Does not recompute keys, interpret unproven cardinality as many-to-many, or
/// discharge authored uniqueness or null-key requirements. Row-order preservation
/// is a future execution obligation, not a new total-order witness.
pub fn link_program_join_requirements(
  index : ProgramOperationResolutionIndex,
  max_work : Int,
  max_links : Int,
) -> Result[ProgramOperationResolutionIndex, JoinRequirementIssue] {
  if max_work < 0 || max_links < 0 {
    return Err(InvalidLimits)
  }
  let count = index.states.length()
  if index.work > max_work || count > (max_work - index.work) / 2 {
    return Err(BudgetExceeded)
  }
  let stages = index.requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
  let states = index.states.copy()
  let mut unresolved = index.unresolved
  let mut links = 0
  for i in 0..<count {
    let site = index.requirements.entries[i]
    let kind = match site.requirement {
      @pipeline.JoinRequirement(ResolveCardinality) => 0
      @pipeline.JoinRequirement(PreserveRowOrder) => 2
      @pipeline.JoinRequirement(ResolveOutputLimit)
      | @pipeline.CrossJoinRequirement(ResolveOutputLimit)
      | @pipeline.IntervalJoinRequirement(ResolveOutputLimit) => 1
      _ => continue
    }
    if links == max_links {
      return Err(BudgetExceeded)
    }
    guard states[i] is Unresolved else { return Err(ForeignOccurrence(i)) }
    let stage = stages.contexts[site.stage]
    let visit = stage.visits[site.producer_visit]
    if !physical_equal(
        @parameter_slots.pipeline(visit.collected),
        site.pipeline,
      ) ||
      @pipeline.operation_obligations_scope(site.obligations) != @pipeline.Body {
      return Err(ForeignOccurrence(i))
    }
    if kind == 0 {
      guard @pipeline.join_evidence(site.pipeline, site.step) is Some(evidence) else {
        return Err(MissingEvidence(i))
      }
      states[i] = Resolved(
        JoinCardinality({ requirement_index: i, site, evidence, }),
      )
    } else if kind == 2 {
      guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
        return Err(ForeignOccurrence(i))
      }
      guard step.operation is @pipeline.Join(right~, ..) else {
        return Err(ForeignOccurrence(i))
      }
      guard step.input is Some(left) else { return Err(ForeignOccurrence(i)) }
      states[i] = Execution(
        JoinRowOrder({
          site,
          step,
          left,
          right,
          left_order: @pipeline.logical_order(site.pipeline, left),
          right_order: @pipeline.logical_order(site.pipeline, right),
          output_order: @pipeline.logical_order(
            site.pipeline,
            @pipeline.Step(site.step),
          ),
        }),
      )
    } else {
      let capacity = stage.context.capacity
      guard @capacity.application_closure_at(capacity, site.producer_visit)
        is Some(application) else {
        return Err(MissingCapacity(i))
      }
      guard @capacity.consumer_coverage_joins(
          @capacity.application_coverage_consumers(application),
        )
        is Some(joins) else {
        return Err(MissingCapacity(i))
      }
      guard @step_bounds.join_application_at(joins, site.step) is Some(limit) else {
        return Err(MissingCapacity(i))
      }
      if !physical_equal(@step_bounds.join_limit_pipeline(limit), site.pipeline) ||
        @step_bounds.join_limit_step(limit) != site.step ||
        @policy.cid(@step_bounds.join_limit_policy(limit)) !=
        @policy.cid(stages.policy) {
        return Err(ForeignOccurrence(i))
      }
      states[i] = Execution(JoinOutputLimit({ site, capacity, limit, }))
    }
    links += 1
    unresolved -= 1
  }
  Ok({ ..index, states, unresolved, work: index.work + count * 2, })
}
