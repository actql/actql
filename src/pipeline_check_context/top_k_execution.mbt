///|
pub enum TopKExecutionRule {
  SelectOrderedPrefix
  PartitionByCanonicalKeys
}

///|
pub struct TopKExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @relation.CheckedOperation
  count : @relation.CountValue
  policy : @policy.Policy
  output_ceiling : @policy.Ceiling
  rule : TopKExecutionRule
}

///|
// The enclosing closure must also resolve the owned order and Parameter count.
// This check is neither proof of a total order nor a new row-capacity witness.
fn top_k_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.RelationRequirement(pending) &&
    (
      pending.kind is @relation.TopKSelectionEnvelope ||
      pending.kind is @relation.TopKPartitioning
    ) else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Unary(operation) &&
    (
      @relation.operation(operation) is @relation.TopK ||
      @relation.operation(operation) is @relation.TopKBy
    ) &&
    step.input is Some(input) &&
    @relation.top_k_count(operation) is Some(count) &&
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
  let rule = if pending.kind is @relation.TopKPartitioning {
    if @relation.operation(operation) != @relation.TopKBy {
      return Err(ForeignOccurrence(site.step))
    }
    PartitionByCanonicalKeys
  } else {
    SelectOrderedPrefix
  }
  guard @policy.ceiling(policy, "max_relation_output_rows")
    is Some(output_ceiling) else {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some(
      TopKExecution({
        site,
        step,
        input,
        operation,
        count,
        policy,
        output_ceiling,
        rule,
      }),
    ),
  )
}
