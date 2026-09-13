///|
/// Atomic enforcement of both original, independently scoped limit claims.
pub struct SequenceLimitsCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  limits : @sequence_limits.SequenceLimits
}

///|
fn sequence_limits_check(
  site : OperationRequirementSite,
  limits : @sequence_limits.SequenceLimits,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.SequenceRequirement(AtomicMatchLimits) &&
    @pipeline.operation_obligations_scope(site.obligations) ==
    @pipeline.SequenceSemantics &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Sequence(operation) &&
    @relation.sequence_obligation_at(operation, site.index) ==
    Some(@relation.AtomicMatchLimits) &&
    physical_equal(@sequence_limits.checked_pipeline(limits), site.pipeline) &&
    @sequence_limits.checked_step(limits) == site.step &&
    @policy.cid(@sequence_limits.selected_policy(limits)) == @policy.cid(policy) else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(SequenceLimits({ site, step, limits, }))
}

///|
fn sequence_limits_candidate(
  requirements : ProgramOperationRequirements,
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.SequenceRequirement(AtomicMatchLimits) else {
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
  let applications = @capacity.consumer_coverage_sequence(
    @capacity.application_coverage_consumers(application),
  )
  guard @sequence_limits.application_at(applications, site.step) is Some(limits) else {
    return Ok(None)
  }
  match sequence_limits_check(site, limits, stages.policy) {
    Ok(check) => Ok(Some(check))
    Err(e) => Err(e)
  }
}
