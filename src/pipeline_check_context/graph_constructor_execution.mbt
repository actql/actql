///|
pub(all) enum GraphConstructionRule {
  AdmitPropertyInputRows
  RejectDuplicateKeys
  ExcludeNullKeysAndMissingEndpoints
  EnforcePropertyConstructionEnvelope
} derive(Eq, Debug)

///|
/// A retained check on the existing obligation owner, not an execution owner.
/// Ordered Sample operands include repeated producer visits and definitions.
pub struct GraphConstructionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  operation : @graph.CheckedGraphConstruction
  rule : GraphConstructionRule
  envelope : GraphConstructionEnvelope?
}

///|
fn graph_construction_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.ConstructionRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    AdmitGraphInputRows => AdmitPropertyInputRows
    RejectDuplicateDefinitionKeys => RejectDuplicateKeys
    ExcludeNullKeysAndMissingEndpoints => ExcludeNullKeysAndMissingEndpoints
    ResolveGraphConstructionResources => EnforcePropertyConstructionEnvelope
    ResolveGraphProfile => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.GraphConstruction(inputs~, checked=operation) &&
    site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.operation_obligations_graph_construction(site.obligations)
    is Some(obligation_owner) &&
    physical_equal(obligation_owner, operation) &&
    @graph.construction_pending_at(operation, site.index) == Some(pending) else {
    return Err(ForeignOccurrence(site.step))
  }
  if step.input is Some(_) ||
    @pipeline.input_occurrence_count(step) != inputs.length() ||
    inputs.length() !=
    @graph.construction_node_count(operation) +
    @graph.construction_edge_count(operation) {
    return Err(ForeignOccurrence(site.step))
  }
  for i in 0..<inputs.length() {
    guard @pipeline.input_occurrence_at(step, i)
      is Some({ role: @pipeline.Sample(index), target, }) &&
      index == i &&
      target == inputs[i] else {
      return Err(ForeignOccurrence(site.step))
    }
  }
  let envelope = if rule == EnforcePropertyConstructionEnvelope {
    guard @policy.ceiling(policy, "max_graph_construction_input_rows")
      is Some(input_rows) &&
      @policy.ceiling(policy, "max_graph_construction_nodes")
      is Some(output_nodes) &&
      @policy.ceiling(policy, "max_graph_construction_edges")
      is Some(output_edges) else {
      return Ok(None)
    }
    Some(GraphConstructionEnvelope::{
      policy,
      input_rows,
      output_nodes,
      output_edges,
    })
  } else {
    None
  }
  Ok(
    Some(GraphConstructionExecution({ site, step, operation, rule, envelope, })),
  )
}
