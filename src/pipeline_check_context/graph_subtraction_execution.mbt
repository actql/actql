///|
pub struct GraphSubtractionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  left : @pipeline.Target
  right : @pipeline.Target
  operation : @graph.CheckedSubtraction
  rule : @graph.SubtractionObligation
  policy : @policy.Policy
}

///|
/// Retain exact operand occurrences and the subtraction-specific endpoint
/// closure requirement. This is future enforcement, never a receipt of success.
fn graph_subtraction_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.SubtractionRequirement(rule) else {
    return Ok(None)
  }
  guard site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphSubtraction(right~, checked=operation) &&
    @pipeline.operation_obligations_graph_subtraction(site.obligations)
    is Some(owner) &&
    physical_equal(owner, operation) &&
    @graph.subtraction_pending_at(operation, site.index) == Some(rule) &&
    step.input is Some(left) &&
    @pipeline.input_occurrence_count(step) == 2 &&
    @pipeline.input_occurrence_at(step, 0)
    is Some({ role: @pipeline.Left, target: l, }) &&
    l == left &&
    @pipeline.input_occurrence_at(step, 1)
    is Some({ role: @pipeline.Right, target: r, }) &&
    r == right else {
    return Err(ForeignOccurrence(site.step))
  }
  // Input admission stays with the existing profile linker/provider. Resolving
  // it twice would refuse an ordinary checked Program before candidate selection.
  if rule == @graph.AdmitSubtractionInputs {
    return Ok(None)
  }
  Ok(
    Some(
      GraphSubtractionExecution({
        site,
        step,
        left,
        right,
        operation,
        rule,
        policy,
      }),
    ),
  )
}
