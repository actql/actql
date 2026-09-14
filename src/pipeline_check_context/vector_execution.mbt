///|
pub(all) enum VectorRule {
  AdmitVectorComponents
  RequireVectorIdentityUniqueness
  NormalizeVectorArithmetic
  ComputeVectorScores
  OrderVectorScores
  RequireVectorResources
} derive(Eq, Debug)

///|
pub(all) enum VectorResource {
  ComponentWork
  ValueAndTemporaryBytes
  RetainedVectorState
  ScoreOrderingWork
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
pub fn vector_resource_count(check : VectorCheck) -> Int {
  if check.rule != RequireVectorResources {
    return 0
  }
  if @vector.operation(check.operation) == @vector.ScoreVectors {
    4
  } else {
    3
  }
}

///|
pub fn vector_resource_at(check : VectorCheck, index : Int) -> VectorResource? {
  if check.rule != RequireVectorResources {
    return None
  }
  match index {
    0 => Some(ComponentWork)
    1 => Some(ValueAndTemporaryBytes)
    2 => Some(RetainedVectorState)
    3 if @vector.operation(check.operation) == @vector.ScoreVectors =>
      Some(ScoreOrderingWork)
    _ => None
  }
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
    ResolveVectorResources => RequireVectorResources
    BindQuery(_) | MatchDimensions | ResolveVecaProfile => return Ok(None)
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
