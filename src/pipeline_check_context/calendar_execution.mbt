///|
pub(all) enum CalendarExecutionRule {
  AdmitCalendarValues
  ValidateCalendarBoundaries
  EnforceCalendarOutputEnvelope
} derive(Eq, Debug)

///|
/// Selected semantic artifact and future checks, not evaluated UTC boundaries.
pub struct CalendarExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  operation : @calendar.CheckedCalendar
  selection : OperationCalendarResolution
  range : OperationRangeResolution?
  policy : @policy.Policy
  ceiling : @policy.Ceiling
  rule : CalendarExecutionRule
}

///|
fn calendar_execution_check(
  site : OperationRequirementSite,
  occurrence : Int,
  entries : Array[OperationRequirementSite],
  states : Array[OperationResolutionState],
  selection : OperationCalendarResolution?,
  policy : @policy.Policy,
  max_work : Int,
) -> (Result[OperationExecutionCheck?, OperationResolutionIndexIssue], Int) {
  guard site.requirement is @pipeline.CalendarRequirement(pending) else {
    return (Ok(None), 0)
  }
  let rule = match pending {
    ValidateCalendarValues => AdmitCalendarValues
    ValidateBoundaryDomain => ValidateCalendarBoundaries
    ResolveResources => EnforceCalendarOutputEnvelope
    BindTimestamp(_) | ValidateBoundRange => return (Ok(None), 0)
  }
  guard entries.get(occurrence) is Some(expected) &&
    physical_equal(site, expected) &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Calendar(operation) &&
    selection is Some(selection) &&
    selection.stage == site.stage &&
    selection.producer_visit == site.producer_visit &&
    selection.step == site.step &&
    physical_equal(selection.operation, operation) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @calendar.pending_validation_at(operation, site.index) == Some(pending) &&
    @policy.ceiling(policy, "max_relation_output_rows") is Some(ceiling) else {
    return (Err(ForeignOccurrence(occurrence)), 0)
  }
  let count = @pipeline.operation_obligations_count(site.obligations)
  if max_work < count {
    return (Err(BudgetExceeded), 0)
  }
  let mut range = None
  for slot in 0..<count {
    let index = occurrence - site.index + slot
    guard entries.get(index) is Some(expected) &&
      expected.stage == site.stage &&
      expected.producer_visit == site.producer_visit &&
      expected.step == site.step &&
      physical_equal(expected.pipeline, site.pipeline) &&
      physical_equal(expected.obligations, site.obligations) else {
      return (Err(ForeignOccurrence(occurrence)), slot + 1)
    }
    if expected.requirement is @pipeline.CalendarRequirement(ValidateBoundRange) {
      guard range is None &&
        states.get(index) is Some(Resolved(Range(value))) &&
        value.requirement_index == index &&
        physical_equal(value.site, expected) else {
        return (Err(ForeignOccurrence(occurrence)), slot + 1)
      }
      range = Some(value)
    }
  }
  (
    Ok(
      Some(
        CalendarExecution({
          site,
          step,
          operation,
          selection,
          range,
          policy,
          ceiling,
          rule,
        }),
      ),
    ),
    count,
  )
}
