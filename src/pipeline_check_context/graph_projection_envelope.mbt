///|
/// Output enforcement only; Graph input admission and resource preflight remain
/// separate. This does not certify an observed count or physical memory usage.
pub struct GraphProjectionEnvelope {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @projection.CheckedProjection
  policy : @policy.Policy
  output_rows : @policy.Ceiling
}

///|
fn graph_projection_envelope_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement
    is @pipeline.ProjectionRequirement(ResolveGraphProjectionResources) else {
    return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Projection(operation) &&
    step.input is Some(input) &&
    @projection.output(operation) is @carrier.Relation(_) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @projection.graph_pending_at(operation, site.index) ==
    Some(@projection.ResolveGraphProjectionResources) &&
    @pipeline.input_occurrence_count(step) == 1 else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  guard @policy.ceiling(policy, "max_relation_output_rows") is Some(output_rows) else {
    return Ok(None)
  }
  Ok(
    Some(
      GraphProjectionOutput({
        site,
        step,
        input,
        operation,
        policy,
        output_rows,
      }),
    ),
  )
}
