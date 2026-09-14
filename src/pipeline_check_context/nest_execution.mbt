///|
pub(all) enum NestExecutionRule {
  AdmitAttachedValues
  PreserveNestedDependencies
} derive(Eq, Debug)

///|
/// Future enforcement over the exact parent and child inputs. This is neither
/// a child-order resolution nor evidence that an item or byte ceiling was met.
pub struct NestExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  parent : @pipeline.Target
  child : @pipeline.Target
  operation : @nest.CheckedNest
  rule : NestExecutionRule
}

///|
fn nest_execution_check(
  site : OperationRequirementSite,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.NestRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    ValidateOutputsBeforeConsumers => AdmitAttachedValues
    PropagatePolicyAndCompleteness => PreserveNestedDependencies
    ResolveTotalOrder
    | ResolveItemLimit
    | ResolveNestedEnvelope
    | BindGuard(_) => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Nest(right=child, checked=operation) &&
    step.input is Some(parent) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @nest.pending_validation_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 2 else {
    return Err(ForeignOccurrence(site.step))
  }
  let left = @pipeline.input_occurrence_at(step, 0).unwrap()
  let right = @pipeline.input_occurrence_at(step, 1).unwrap()
  if left.role != @pipeline.Left ||
    left.target != parent ||
    right.role != @pipeline.Right ||
    right.target != child {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(NestExecution({ site, step, parent, child, operation, rule, })))
}
