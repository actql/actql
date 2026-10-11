///|
pub struct GraphMeanCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  inputs : Array[@pipeline.Target]
  operation : @graph.CheckedMean
  rule : @graph.MeanObligation
  policy : @policy.Policy
}

///|
/// Preserve the complete authored sample list and exact obligation owner.
/// This is a future execution check, not successful resource/input evidence.
fn graph_mean_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.MeanRequirement(rule) else {
    return Ok(None)
  }
  guard site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphMean(inputs~, checked=operation) &&
    @pipeline.operation_obligations_graph_mean(site.obligations) is Some(owner) &&
    physical_equal(owner, operation) &&
    @graph.mean_pending_at(operation, site.index) == Some(rule) &&
    inputs.length() ==
    @graph.mean_sample_count(@graph.checked_mean_options(operation)) &&
    inputs.length() >= 1 &&
    @pipeline.input_occurrence_count(step) == inputs.length() else {
    return Err(ForeignOccurrence(site.step))
  }
  for index in 0..<inputs.length() {
    guard @pipeline.input_occurrence_at(step, index) is Some(occurrence) &&
      occurrence.target == inputs[index] &&
      occurrence.role == @pipeline.Sample(index) else {
      return Err(ForeignOccurrence(site.step))
    }
  }
  if rule == @graph.AdmitMeanInputs {
    return Ok(None)
  }
  Ok(
    Some(
      GraphMeanExecution({
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
