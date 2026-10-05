///|
/// Resolve the original checked consumer edge. This value grants neither
/// execution nor access to retained material; producer evidence and Transfer
/// custody must still be admitted by their existing owners.
#export_name("clientValuesHostRetainedInputEdge")
pub fn client_values_host_retained_input_edge(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  consumer_task : Int,
  input_index : Int,
) -> Result[@host.ClientRetainedInputEdge, @host.ClientRetainedInputIssue] {
  @host.prepare_client_retained_input_edge(
    prepared, compilation, admission, definition, consumer_task, input_index,
  )
}

///|
#export_name("clientValuesHostRetainedInputEdgeFacts")
pub fn client_values_host_retained_input_edge_facts(
  edge : @host.ClientRetainedInputEdge,
) -> Array[String] {
  let facts = @host.client_retained_input_edge_projection(edge)
  facts.push(@host.client_retained_input_edge_schema_cid(edge))
  facts
}
