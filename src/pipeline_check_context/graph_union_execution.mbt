///|
pub struct GraphUnionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  inputs : Array[@pipeline.Target]
  operation : @graph.CheckedUnion
  rule : @graph.UnionObligation
  policy : @policy.Policy
}

///|
/// Retain future runtime obligations, never successful input/resource receipts.
/// Every authored occurrence stays distinct, including repeated target names.
fn graph_union_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.UnionRequirement(rule) else {
    return Ok(None)
  }
  guard site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphUnion(inputs~, checked=operation) &&
    @pipeline.operation_obligations_graph_union(site.obligations) is Some(owner) &&
    physical_equal(owner, operation) &&
    @graph.union_pending_at(operation, site.index) == Some(rule) &&
    inputs.length() == @graph.union_input_count(operation) &&
    inputs.length() >= 2 &&
    @pipeline.input_occurrence_count(step) == inputs.length() else {
    return Err(ForeignOccurrence(site.step))
  }
  for index in 0..<inputs.length() {
    guard @pipeline.input_occurrence_at(step, index) is Some(occurrence) &&
      occurrence.target == inputs[index] &&
      occurrence.role ==
      (if index == 0 { @pipeline.Primary } else { @pipeline.Sample(index) }) else {
      return Err(ForeignOccurrence(site.step))
    }
  }
  if rule == @graph.AdmitUnionInputs {
    return Ok(None)
  }
  Ok(
    Some(
      GraphUnionExecution({
        site,
        step,
        inputs: inputs.copy(),
        operation,
        rule,
        policy,
      }),
    ),
  )
}
