///|
/// A selected output enforcement ceiling, not an observed count or a bound on
/// input validation, ordering work, retained copies or backend memory.
pub struct EventOutputEnvelope {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @event.CheckedEvent
  policy : @policy.Policy
  ceiling : @policy.Ceiling
}

///|
fn event_output_envelope_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.EventRequirement(ResolveEventResources) else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Event(operation) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @event.pending_validation_at(operation, site.index) ==
    Some(@event.ResolveEventResources) &&
    @pipeline.input_occurrence_count(step) == 1 else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  let field = match @event.output(operation) {
    @carrier.Relation(_) => "max_relation_output_rows"
    @carrier.EventValue(_) => "max_temporal_output_rows"
    _ => return Err(ForeignOccurrence(site.step))
  }
  guard @policy.ceiling(policy, field) is Some(ceiling) else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(EventEnvelope({ site, step, input, operation, policy, ceiling, })))
}
