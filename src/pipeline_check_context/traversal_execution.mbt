///|
/// Search-path and emitted-row limits remain separate, owned enforcement inputs.
/// This binding neither executes traversal nor certifies successful enforcement.
pub struct TraversalLimitsCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  limits : @step_bounds.TraversalLimits
}

///|
fn traversal_limits_check(
  site : OperationRequirementSite,
  limits : @step_bounds.TraversalLimits,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck, OperationResolutionIndexIssue] {
  guard site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    physical_equal(@step_bounds.traversal_limit_pipeline(limits), site.pipeline) &&
    @step_bounds.traversal_limit_step(limits) == site.step &&
    physical_equal(@step_bounds.traversal_limit_policy(limits), policy) else {
    return Err(ForeignOccurrence(site.step))
  }
  let check : TraversalLimitsCheck = { site, step, limits, }
  match (site.requirement, step.operation) {
    (
      @pipeline.TraverseRequirement(requirement),
      @pipeline.Traverse(checked=operation, ..),
    ) => {
      if @graph.traverse_pending_at(operation, site.index) != Some(requirement) {
        return Err(ForeignOccurrence(site.step))
      }
      match requirement {
        ResolveTraversalResources => Ok(TraversalLimits(check))
        EnforceTraversalOutputGuard =>
          if @step_bounds.traversal_limit_guard_value(limits) is Some(_) {
            Ok(TraversalOutputGuard(check))
          } else {
            Err(ForeignOccurrence(site.step))
          }
        _ => Err(ForeignOccurrence(site.step))
      }
    }
    _ => Err(ForeignOccurrence(site.step))
  }
}

///|
fn traversal_limits_candidate(
  requirements : ProgramOperationRequirements,
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement
    is @pipeline.TraverseRequirement(
      ResolveTraversalResources
      | EnforceTraversalOutputGuard
    ) else {
    return Ok(None)
  }
  let stages = requirements.stages
  guard stages.contexts.get(site.stage) is Some(stage) &&
    stage.visits.get(site.producer_visit) is Some(visit) &&
    physical_equal(@parameter_slots.pipeline(visit.collected), site.pipeline) &&
    @capacity.application_closure_at(
      stage.context.capacity,
      site.producer_visit,
    )
    is Some(application) else {
    return Err(ForeignOccurrence(site.step))
  }
  guard @capacity.consumer_coverage_traversals(
      @capacity.application_coverage_consumers(application),
    )
    is Some(applications) &&
    @step_bounds.traversal_application_at(applications, site.step)
    is Some(limits) else {
    return Ok(None)
  }
  match traversal_limits_check(site, limits, stages.policy) {
    Ok(check) => Ok(Some(check))
    Err(error) => Err(error)
  }
}
