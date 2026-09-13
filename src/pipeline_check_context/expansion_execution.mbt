///|
pub enum ExpansionExecutionRule {
  EmitUnpivotOccurrences
  EmitArrayOccurrences
  EnforceOutputEnvelope(@policy.Ceiling)
}

///|
pub struct ExpansionExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
  policy : @policy.Policy
  rule : ExpansionExecutionRule
}

///|
// A runtime envelope is not a row-count proof or an input-order witness.
fn expansion_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) &&
    (
      pending.kind is @relation.ValidateReshapeRows ||
      pending.kind is @relation.ExpansionEnvelope
    ) else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Unary(operation) &&
    (
      @relation.operation(operation) is @relation.Unpivot ||
      @relation.operation(operation) is @relation.Unnest
    ) else {
    return Ok(None)
  }
  guard step.input is Some(input) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.input_occurrence_count(step) == 1 &&
    @relation.pending_validation_at(operation, site.index) is Some(owned) else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary ||
    edge.target != input ||
    owned.kind != pending.kind ||
    !physical_equal(owned.source, pending.source) {
    return Err(ForeignOccurrence(site.step))
  }
  let rule = if pending.kind is @relation.ExpansionEnvelope {
    guard @policy.ceiling(policy, "max_relation_output_rows") is Some(ceiling) else {
      return Err(ForeignOccurrence(site.step))
    }
    ExpansionExecutionRule::EnforceOutputEnvelope(ceiling)
  } else if @relation.operation(operation) is @relation.Unpivot {
    EmitUnpivotOccurrences
  } else {
    EmitArrayOccurrences
  }
  Ok(Some(ExpansionExecution({ site, step, input, operation, policy, rule, })))
}
