///|
/// The two retained engine-atomic claims have different units and subjects.
/// Binding them does not assert that input admission or enforcement has run.
pub struct ComponentsLimitsCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  limits : @step_bounds.ComponentsLimits
}

///|
fn components_limits_check(
  site : OperationRequirementSite,
  limits : @step_bounds.ComponentsLimits,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.GraphRequirement(requirement) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Graph(operation) &&
    @graph.operation(operation) == @graph.Components &&
    @graph.pending_validation_at(operation, site.index) == Some(requirement) &&
    physical_equal(
      @step_bounds.components_limit_pipeline(limits),
      site.pipeline,
    ) &&
    @step_bounds.components_limit_step(limits) == site.step &&
    @policy.cid(@step_bounds.components_limit_policy(limits)) ==
    @policy.cid(policy) else {
    return Err(ForeignOccurrence(site.step))
  }
  let check : ComponentsLimitsCheck = { site, step, limits, }
  match requirement {
    ResolveGraphResources => Ok(ComponentsLimits(check))
    EnforceOutputGuard if @step_bounds.components_limit_guard_value(limits)
      is Some(_) => Ok(ComponentsOutputGuard(check))
    _ => Err(ForeignOccurrence(site.step))
  }
}

///|
fn components_limits_candidate(
  requirements : ProgramOperationRequirements,
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement
    is @pipeline.GraphRequirement(ResolveGraphResources | EnforceOutputGuard) else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Graph(operation) else {
    return Err(ForeignOccurrence(site.step))
  }
  if @graph.operation(operation) != @graph.Components {
    return Ok(None)
  }
  let stages = requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
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
  guard @capacity.consumer_coverage_components(
      @capacity.application_coverage_consumers(application),
    )
    is Some(applications) &&
    @step_bounds.components_application_at(applications, site.step)
    is Some(limits) else {
    return Ok(None)
  }
  match components_limits_check(site, limits, stages.policy) {
    Ok(check) => Ok(Some(check))
    Err(e) => Err(e)
  }
}
