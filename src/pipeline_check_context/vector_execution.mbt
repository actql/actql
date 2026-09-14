///|
pub(all) enum VectorRule {
  AdmitVectorComponents
  RequireVectorIdentityUniqueness
  NormalizeVectorArithmetic
  ComputeVectorScores
  OrderVectorScores
} derive(Eq, Debug)

///|
pub struct VectorCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @vector.CheckedVector
  rule : VectorRule
  policy : @policy.Policy
}

///|
fn vector_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.VectorRequirement(pending) else {
    return Ok(None)
  }
  let rule : VectorRule = match pending {
    ValidateVectorValues => AdmitVectorComponents
    ValidateUniqueIdentities => RequireVectorIdentityUniqueness
    NormalizeArithmetic => NormalizeVectorArithmetic
    ScoreArithmetic => ComputeVectorScores
    ScoreOrder => OrderVectorScores
    BindQuery(_)
    | MatchDimensions
    | ResolveVecaProfile
    | ResolveVectorResources => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Vector(operation) &&
    step.input is Some(input) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @vector.pending_validation_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @pipeline.input_occurrence_at(step, 0) is Some(edge) &&
    edge.role == @pipeline.Primary &&
    edge.target == input else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(Some(VectorExecution({ site, step, input, operation, rule, policy, })))
}
