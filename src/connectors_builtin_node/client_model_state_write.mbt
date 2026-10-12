///|
// Private Node installation seam. The existing checked scope/Writer Owner
// supplies the original read; these exports issue no numeric/recovery/send grant.
#export_name("clientProgramPrepareInferNodeReadState")
pub fn client_program_prepare_infer_node_read_state(
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
  layout : @publication_host.ClientNodeModelPreparationLayout?,
  installation : @check_environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @check_environment.DecisionProbabilityProfile?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientNodeModelStateWriter,
  @publication_host.ClientNodeModelStateIssue,
] {
  @publication_host.prepare_client_node_model_read_state(
    scope, compiled, definition, graph, layout, installation, runtime_artifact_cid,
    layout_artifact_cid, probability, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramInferNodeReadStateRead")
pub fn client_program_infer_node_read_state_read(
  value : @publication_host.ClientNodeModelStateWriter,
) -> Result[
  @publication_host.ClientModelReadPreparation,
  @publication_host.ClientNodeModelStateIssue,
] {
  @publication_host.client_node_model_state_read(value)
}

///|
#export_name("clientProgramAdvanceInferNodeReadState")
pub fn client_program_advance_infer_node_read_state(
  value : @publication_host.ClientNodeModelStateWriter,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
  quantum : Int,
) -> @resources.OriginalStateWritePoll {
  @publication_host.advance_client_node_model_read_state(
    value, compiled, definition, graph, quantum,
  )
}

///|
#export_name("clientProgramInferNodeReadStatePoll")
pub fn client_program_infer_node_read_state_poll(
  poll : @resources.OriginalStateWritePoll,
) -> (String, Int, @resources.OriginalStateWriteIssue?) {
  match poll {
    @resources.StateWriteContinue(work~) => ("continue", work, None)
    @resources.StateWriteComplete(work~) => ("complete", work, None)
    @resources.StateWriteFailed(issue, work~) => ("failed", work, Some(issue))
  }
}

///|
#export_name("clientProgramFinishInferNodeReadState")
pub fn client_program_finish_infer_node_read_state(
  value : @publication_host.ClientNodeModelStateWriter,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[String, @publication_host.ClientNodeModelStateIssue] {
  @publication_host.finish_client_node_model_read_state(
    value, compiled, definition, graph,
  )
}

///|
#export_name("clientProgramStopInferNodeReadState")
pub fn client_program_stop_infer_node_read_state(
  value : @publication_host.ClientNodeModelStateWriter,
  scope : @publication_host.ClientModelReadScope,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
) -> Result[Unit, @publication_host.ClientModelReadPreparationIssue] {
  @publication_host.stop_client_node_model_read_state(
    value, scope, compiled, definition, graph,
  )
}

///|
#export_name("clientProgramSettleInferNodeReadState")
pub fn client_program_settle_infer_node_read_state(
  value : @publication_host.ClientNodeModelStateWriter,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
  physical_cleanup_complete : Bool,
) -> Result[Unit, @publication_host.ClientModelReadPreparationIssue] {
  @publication_host.settle_client_node_model_read_state(
    value, compiled, definition, graph, physical_cleanup_complete,
  )
}
