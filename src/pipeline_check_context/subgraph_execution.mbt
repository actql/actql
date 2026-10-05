///|
pub(all) enum SubgraphExecutionRule {
  AdmitSubgraphGraph
  InduceSubgraphEndpoints
  FilterSubgraphEdges
  PreserveSubgraphIdentities
  PreserveSubgraphPolicy
  EnforceSubgraphResources
} derive(Eq, Debug)

///|
pub struct SubgraphExecutionCheck {
  site : OperationRequirementSite
  step : @pipeline.CheckedStep
  graph : @pipeline.Target
  relation : @pipeline.Target?
  operation : @graph.CheckedSubgraph
  rule : SubgraphExecutionRule
  policy : @policy.Policy
  output_nodes : @policy.Ceiling
  output_edges : @policy.Ceiling
}

///|
fn subgraph_execution_check(
  site : OperationRequirementSite,
  policy : @policy.Policy,
) -> Result[OperationExecutionCheck?, OperationResolutionIndexIssue] {
  guard site.requirement is @pipeline.SubgraphRequirement(pending) else {
    return Ok(None)
  }
  let rule = match pending {
    AdmitSubgraphInput => AdmitSubgraphGraph
    InduceSelectedEndpoints => InduceSubgraphEndpoints
    FilterInducedEdges => FilterSubgraphEdges
    PreserveSubgraphIdentitiesAndProperties => PreserveSubgraphIdentities
    PreserveSubgraphPolicyAndScope => PreserveSubgraphPolicy
    ResolveSubgraphResources => EnforceSubgraphResources
    ResolveSubgraphProfile => return Ok(None)
  }
  guard site.group == 0 &&
    @pipeline.operation_obligations_scope(site.obligations) == @pipeline.Body &&
    @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Subgraph(selector=relation, checked=operation) &&
    step.input is Some(graph) &&
    @pipeline.operation_obligations_subgraph(site.obligations) is Some(owner) &&
    physical_equal(owner, operation) &&
    @graph.subgraph_pending_at(operation, site.index) == Some(pending) &&
    @pipeline.input_occurrence_count(step) ==
    (if relation is Some(_) { 2 } else { 1 }) &&
    @pipeline.input_occurrence_at(step, 0)
    is Some({ role: @pipeline.Primary, target, }) &&
    target == graph else {
    return Err(ForeignOccurrence(site.step))
  }
  if relation is Some(expected) {
    guard @pipeline.input_occurrence_at(step, 1)
      is Some({ role: @pipeline.Right, target, }) &&
      target == expected &&
      @graph.selector_form(@graph.subgraph_nodes(operation))
      is @graph.RelationIds(..) else {
      return Err(ForeignOccurrence(site.step))
    }
  } else if @graph.selector_form(@graph.subgraph_nodes(operation))
    is @graph.RelationIds(..) {
    return Err(ForeignOccurrence(site.step))
  }
  guard @policy.ceiling(policy, "max_graph_construction_nodes")
    is Some(output_nodes) &&
    @policy.ceiling(policy, "max_graph_construction_edges")
    is Some(output_edges) else {
    return Ok(None)
  }
  Ok(
    Some(
      SubgraphExecution({
        site,
        step,
        graph,
        relation,
        operation,
        rule,
        policy,
        output_nodes,
        output_edges,
      }),
    ),
  )
}
