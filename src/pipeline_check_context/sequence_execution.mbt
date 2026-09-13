///|
pub(all) enum SequenceExecutionRule {
  AdmitSequenceValues
  ValidateSequenceIdentities
  OrderSequenceEvents
} derive(Eq, Debug)

///|
/// Matcher-input duties, not successful admission or an input total-order claim.
pub struct SequenceExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedSequence
  rule : SequenceExecutionRule
}

///|
fn sequence_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.SequenceRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    ValidateEventValues => AdmitSequenceValues
    UniqueEventIdentity => ValidateSequenceIdentities
    AscendingEventOrder => OrderSequenceEvents
    BoundedMatchSearch | AtomicMatchLimits | TeaProfile | BindWithin(_) =>
      return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Sequence(operation) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) ==
    @pipeline.SequenceSemantics &&
    @relation.sequence_obligation_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 1 else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(SequenceExecution({ site, step, input, operation, rule, })))
}
