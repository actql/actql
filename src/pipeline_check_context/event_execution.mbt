///|
pub(all) enum EventExecutionRule {
  AdmitEventValues
  ValidateEventIdentities
  ConvertEventClock
  ClassifyEventWatermark
  SelectEventRepresentative
} derive(Eq, Debug)

///|
/// An owned future check, not successful admission, selection or resource proof.
/// The checked operation retains the exact role contracts and authored options.
pub struct EventExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @event.CheckedEvent
  rule : EventExecutionRule
}

///|
fn event_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.EventRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    ValidateEventValues => AdmitEventValues
    ValidateUniqueIdentities => ValidateEventIdentities
    ConvertTimestampClock => ConvertEventClock
    WatermarkClassification => ClassifyEventWatermark
    FailOnTopTie => SelectEventRepresentative
    ResolveTeaProfile
    | ResolveEventResources
    | BindGap(_)
    | SessionArithmetic
    | SessionIdentity => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Event(operation) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @event.pending_validation_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 1 else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(EventExecution({ site, step, input, operation, rule, })))
}
