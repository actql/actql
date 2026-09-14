///|
/// A statically selected expansion to journal, not an executed traversal.
/// The retained operation supplies the semantic output contract and aliases.
pub struct ReachExpansion {
  requirement_index : Int
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  input : @pipeline.Target
  operation : @graph.CheckedReach
  start : @value.CheckedValue
  direction : @graph.Direction
  minimum_hops : Double
  maximum_hops : Double
  emission : @graph.PathOutput
}

///|
fn reach_expansion(
  site : OperationRequirementSite,
  requirement_index : Int,
) -> Result[ReachExpansion?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.ReachRequirement(JournalReachExpansion) else {
    return Ok(None)
  }
  guard requirement_index >= 0 &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Reach(operation) &&
    step.input is Some(input) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.reach_pending_at(operation, site.index) ==
    Some(JournalReachExpansion) &&
    @pipeline.input_occurrence_count(step) == 1 else {
    return Err(ForeignOccurrence(site.step))
  }
  let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
  if edge.role != @pipeline.Primary || edge.target != input {
    return Err(ForeignOccurrence(site.step))
  }
  Ok(
    Some({
      requirement_index,
      site,
      step,
      input,
      operation,
      start: @graph.reach_start(operation),
      direction: @graph.reach_direction(operation),
      minimum_hops: 0.0,
      maximum_hops: @graph.reach_max_depth(operation),
      emission: @graph.TraversedNodes,
    }),
  )
}
