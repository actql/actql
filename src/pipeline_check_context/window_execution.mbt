///|
pub enum WindowExecutionRule {
  AdmitTimeValues
  AssignMemberships
}

///|
pub struct WindowExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  window : @window.CheckedWindow
  rule : WindowExecutionRule
}

///|
fn window_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.WindowRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    ValidateTimeValues => AdmitTimeValues
    CheckedWindowArithmetic => AssignMemberships
    BindMilliseconds(_, _)
    | ResolveMembershipBound
    | ResolvePublicationResources => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Window(window) &&
    step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @window.pending_validation_at(window, site.index) is Some(owned) &&
    owned == pending else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(WindowExecution({ site, step, input, window, rule, })))
}
