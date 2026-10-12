///|
// Explicit prepaid census operation, not an ordinary park reinterpretation.
// The actual original operation retains its park even if later codec/Store
// work fails. This port neither supplies numerical funding nor changes CID.
#export_name("clientProgramParkInferOriginalModelResourcesForStateWrite")
pub fn client_program_park_infer_original_model_resources_for_state_write(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
) -> Result[@publication_host.ClientModelResourcePark, @infer_host.Issue] {
  @infer_host.park_original_model_resources_for_state_write(active, scope)
}

///|
#export_name("clientProgramPrepareInferOriginalCurrentStateWriter")
pub fn client_program_prepare_infer_original_current_state_writer(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @infer_host.OriginalModelCurrentStateWriter,
  @resources.OriginalStateWriteIssue,
] {
  @infer_host.prepare_original_model_current_state_writer(
    active, scope, park, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramAdvanceInferOriginalCurrentStateWriter")
pub fn client_program_advance_infer_original_current_state_writer(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  value : @infer_host.OriginalModelCurrentStateWriter,
  quantum : Int,
) -> @resources.OriginalStateWritePoll {
  @infer_host.advance_original_model_current_state_writer(
    active, scope, park, value, quantum,
  )
}

///|
#export_name("clientProgramFinishInferOriginalCurrentStateWriter")
pub fn client_program_finish_infer_original_current_state_writer(
  active : @infer_host.Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  value : @infer_host.OriginalModelCurrentStateWriter,
) -> Result[String, @resources.OriginalStateWriteIssue] {
  @infer_host.finish_original_model_current_state_writer(
    active, scope, park, value,
  )
}

///|
#export_name("clientProgramCancelInferOriginalCurrentStateWriter")
pub fn client_program_cancel_infer_original_current_state_writer(
  value : @infer_host.OriginalModelCurrentStateWriter,
) -> Unit {
  @infer_host.cancel_original_model_current_state_writer(value)
}
