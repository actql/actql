///|
// Private installed Node ports. These exports do not enable an asynchronous
// profile or confer capacity, capture installation or raw disclosure rights.
#export_name("clientProgramReadModelResponseProfile")
pub fn client_program_read_model_response_profile(
  wire : String,
  expected_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  max_work : Int,
) -> Result[
  @check_environment.ModelResponseProfile,
  @check_environment.ModelTaskIssue,
] {
  @check_environment.read_model_response_profile(
    @utf8.encode(wire),
    expected_cid,
    { max_bytes, max_nodes, max_depth, max_members, },
    max_work,
  )
}

///|
#export_name("clientProgramBindModelRawCapturePolicy")
pub fn client_program_bind_model_raw_capture_policy(
  policy : @publication.RunEvidenceValue,
  retention : @publication.CapturedEffectDependencyBody,
  metadata : @publication.CapturedEffectDependencyBody,
  clock : @publication.CapturedEffectDependencyBody,
  data : @publication.CapturedEffectDependencyBody,
) -> Result[
  @publication.BoundModelRawCapturePolicy,
  @publication.RunEvidenceValueIssue,
] {
  @publication.bind_model_raw_capture_policy(
    policy, retention, metadata, clock, data,
  )
}

///|
/// Issue the existing policy body from original typed owners and fixed Host
/// selection values. It is not capture permission or a Store observation.
#export_name("clientProgramIssueInferRawCapturePolicy")
pub fn client_program_issue_infer_raw_capture_policy(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  dispatch : @publication_host.ClientInferDispatchAdmission,
  scope : @publication.BoundModelInvocationScope,
  profile : @check_environment.ModelResponseProfile,
  installation : @check_environment.ModelResponseProfileInstallation,
  probability : @check_environment.DecisionProbabilityProfile?,
  store_authority_cid : String,
  retention : @publication.CapturedEffectDependencyBody,
  metadata : @publication.CapturedEffectDependencyBody,
  clock : @publication.CapturedEffectDependencyBody,
  data : @publication.CapturedEffectDependencyBody,
  selected_at : String,
  available_until : String,
  delete_by : String,
  extension_ceiling_at : String,
  metadata_delete_by : String,
) -> Result[
  @publication.BoundModelRawCapturePolicy,
  @publication_host.ClientModelRawCaptureIssue,
] {
  if !@publication_host.client_infer_dispatch_matches_run(dispatch, compiled, definition) {
    return Err(@publication_host.ForeignRun)
  }
  @publication_host.issue_client_model_raw_capture_policy(
    dispatch, scope, profile, installation, probability, store_authority_cid,
    retention, metadata, clock, data, selected_at, available_until, delete_by,
    extension_ceiling_at, metadata_delete_by,
  )
}

///|
/// Match the original compiled owner before delegating installed selection and
/// current authorization to the existing registration Owner. No CID-only grant.
#export_name("clientProgramRegisterInferRawCapture")
pub fn client_program_register_infer_raw_capture(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  dispatch : @publication_host.ClientInferDispatchAdmission,
  scope : @publication.BoundModelInvocationScope,
  policy : @publication.BoundModelRawCapturePolicy,
  profile : @check_environment.ModelResponseProfile,
  installation : @check_environment.ModelResponseProfileInstallation,
  probability : @check_environment.DecisionProbabilityProfile?,
  account : AuthorizationAccount,
  at : String,
  store_authority_cid : String,
  selection_available : () -> Bool,
  observe_account : () -> AuthorizationAccount,
  observe_at : () -> String,
  delegated : AuthorizationDecision?,
) -> Result[
  @publication_host.ClientModelRawCaptureRegistration,
  @publication_host.ClientModelRawCaptureIssue,
] {
  if !@publication_host.client_infer_dispatch_matches_run(
      dispatch, compiled, definition,
    ) {
    return Err(@publication_host.ForeignRun)
  }
  guard account.state is @authorization.Admitted(current) else {
    return Err(@publication_host.Authorization(@authorization.Denied))
  }
  @publication_host.register_client_model_raw_capture(
    dispatch,
    scope,
    policy,
    profile,
    installation,
    probability,
    current,
    at,
    store_authority_cid,
    selection_available,
    () => {
      guard observe_account().state is @authorization.Admitted(current) else {
        return Err(@publication_host.Authorization(@authorization.Denied))
      }
      Ok((current, observe_at()))
    },
    delegated_action=match delegated {
      Some(value) => value.action
      None => None
    },
  )
}

///|
#export_name("clientProgramInferRawCaptureSaveBinding")
pub fn client_program_infer_raw_capture_save_binding(
  value : @model.ModelRawCaptureSave,
) -> (String, String, String, String, Int) {
  @publication.model_raw_response_store_binding(
    @model.model_raw_capture_save_binding(value),
  )
}

///|
#export_name("clientProgramInferRawCaptureSaveOriginals")
pub fn client_program_infer_raw_capture_save_originals(
  value : @model.ModelRawCaptureSave,
) -> Array[(String, String, String)] {
  @model.model_raw_capture_save_originals(value).map(original => {
    (
      @publication.captured_effect_dependency_body_kind(original),
      @publication.captured_effect_dependency_body_cid(original),
      @publication.captured_effect_dependency_body_json(original),
    )
  })
}

///|
#export_name("clientProgramInferRawCaptureSaveCurrent")
pub fn client_program_infer_raw_capture_save_current(
  value : @model.ModelRawCaptureSave,
) -> Result[Unit, @model.ModelRawCaptureSaveIssue] {
  @model.model_raw_capture_save_current(value)
}

///|
#export_name("clientProgramAcknowledgeSavedInferRawCapture")
pub fn client_program_acknowledge_saved_infer_raw_capture(
  value : @model.ModelRawCaptureSave,
) -> Result[@model.ModelSavedRawReceipt, @model.ModelRawCaptureSaveIssue] {
  @model.acknowledge_saved_model_raw_capture(value)
}

///|
#export_name("clientProgramInferSavedRawReceiptMatches")
pub fn client_program_infer_saved_raw_receipt_matches(
  receipt : @model.ModelSavedRawReceipt,
  call : @model.ModelPhysicalCall,
  response : @publication.RunEvidenceValue,
) -> Bool {
  @model.model_saved_raw_receipt_matches(receipt, call, response)
}

///|
#export_name("clientProgramInferSavedRawChatResponse")
pub fn client_program_infer_saved_raw_chat_response(
  receipt : @model.ModelSavedRawReceipt,
  body : String,
  metadata : @identity.CanonicalValue?,
) -> Result[@model.ModelPhysicalChatResponse, @model.ModelRawCaptureSaveIssue] {
  @model.model_saved_raw_chat_response(receipt, body, metadata)
}
