///|
pub(all) enum GraphConstructionRule {
  AdmitInputRows
  CloseDeclaredEndpoints
  DeriveEndpointNodes
  JournalEndpoints
  JournalLabels
  CollapseEqualPayloads
  RejectPayloadConflicts
  EnforceConstructionEnvelope
} derive(Eq, Debug)

///|
/// Exact ordered operands remain on step; repeated operands are not deduplicated.
/// A retained check is not evidence of executed construction or resource admission.
pub struct GraphConstructionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  nodes : @pipeline.Target?
  edges : @pipeline.Target
  operation : @graph.CheckedConstruction
  rule : GraphConstructionRule
  envelope : GraphConstructionEnvelope?
}

///|
pub struct GraphConstructionEnvelope {
  policy : @policy.Policy
  input_rows : @policy.Ceiling
  output_nodes : @policy.Ceiling
  output_edges : @policy.Ceiling
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
    AdmitGraphInputRows => AdmitInputRows
    CloseBothEndpointsAgainstDeclaredNodes => CloseDeclaredEndpoints
    DeriveDistinctEndpointNodes => DeriveEndpointNodes
    JournalEndpointCompletion => JournalEndpoints
    JournalLabelCompletion => JournalLabels
    CollapseEqualIdentityPayloads => CollapseEqualPayloads
    RejectConflictingIdentityPayloads => RejectPayloadConflicts
    ResolveGraphConstructionResources => EnforceConstructionEnvelope
    ResolveSgaProfile => return Ok(None)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation
    is @pipeline.GraphConstruction(nodes~, edges~, checked=operation) &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @graph.construction_pending_at(operation, site.index) == Some(pending) else {
    return Err(ForeignOccurrence(site.step))
  }
  match nodes {
    Some(node) => {
      if step.input is Some(_) || @pipeline.input_occurrence_count(step) != 2 {
        return Err(ForeignOccurrence(site.step))
      }
      let left = @pipeline.input_occurrence_at(step, 0).unwrap()
      let right = @pipeline.input_occurrence_at(step, 1).unwrap()
      if left.role != @pipeline.Left ||
        left.target != node ||
        right.role != @pipeline.Right ||
        right.target != edges {
        return Err(ForeignOccurrence(site.step))
      }
    }
    None => {
      if step.input != Some(edges) ||
        @pipeline.input_occurrence_count(step) != 1 {
        return Err(ForeignOccurrence(site.step))
      }
      let edge = @pipeline.input_occurrence_at(step, 0).unwrap()
      if edge.role != @pipeline.Primary || edge.target != edges {
        return Err(ForeignOccurrence(site.step))
      }
    }
  }
  let envelope = if rule == EnforceConstructionEnvelope {
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
    Some(
      GraphConstructionExecution({
        site,
        step,
        nodes,
        edges,
        operation,
        rule,
        envelope,
      }),
    ),
  )
}
