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
  property_graph_construction_execution_check(site, policy)
}
