///|
// Private installed physical ports only. These bindings reuse the existing
// Model Owner and do not advertise a funded public asynchronous capability.
#export_name("clientProgramModelAsyncPhysicalRequestPlan")
pub fn client_program_model_async_physical_request_plan(
  request : @model.ModelRequest,
  wire_bytes : Int64,
  tokens : Int64,
  cost_units : Int64,
  duration_ms : Int64,
  profile : @check_environment.ModelResponseProfile,
  installation : @check_environment.ModelResponseProfileInstallation,
  start : (@model.ModelCallEntry) -> @model.ModelPhysicalCall?,
) -> Result[@model.ModelPhysicalRequestPlan, @model.ModelExecutionIssue] {
  @model.model_async_physical_request_plan(
    request,
    wire_bytes,
    { tokens, cost_units, duration_ms, },
    profile,
    installation,
    start,
  )
}

///|
// Private native Decision installation only; this preserves the exact original
// projection membership and consumes no generation setting or dummy executor.
#export_name("clientProgramModelAsyncNativeDecisionRequestPlan")
pub fn client_program_model_async_native_decision_request_plan(
  request : @model.ModelRequest,
  original : @model.NativeDecisionRequest,
  provider : @model.AdmittedModelProvider,
  wire_bytes : Int64,
  tokens : Int64,
  cost_units : Int64,
  duration_ms : Int64,
  profile : @check_environment.ModelResponseProfile,
  installation : @check_environment.ModelResponseProfileInstallation,
  probability : @check_environment.DecisionProbabilityProfile,
  start : (@model.ModelCallEntry) -> @model.ModelPhysicalCall?,
) -> Result[@model.ModelPhysicalRequestPlan, @model.ModelExecutionIssue] {
  @model.model_async_native_decision_request_plan(
    request,
    original,
    provider,
    wire_bytes,
    { tokens, cost_units, duration_ms, },
    profile,
    installation,
    probability,
    start,
  )
}

///|
/// Retain custody of the original consumed Entry before fixed transport start.
#export_name("clientProgramModelPhysicalCall")
pub fn client_program_model_physical_call(
  entry : @model.ModelCallEntry,
  prepared : @model.ModelPreparedCallSet,
  poll : () -> @model.ModelPhysicalCallPoll,
  cancel : () -> Unit,
  cleanup : (Bool) -> Bool,
) -> @model.ModelPhysicalCall? {
  @model.model_physical_call(entry, prepared, poll, cancel, cleanup)
}

///|
/// Bind the fixed original request to the consumed Entry through Common.
#export_name("clientProgramModelPhysicalCallForRequest")
pub fn client_program_model_physical_call_for_request(
  entry : @model.ModelCallEntry,
  request : @model.ModelRequest,
  poll : () -> @model.ModelPhysicalCallPoll,
  cancel : () -> Unit,
  cleanup : (Bool) -> Bool,
) -> @model.ModelPhysicalCall? {
  @model.model_physical_call_for_request(entry, request, poll, cancel, cleanup)
}

///|
#export_name("clientProgramModelPhysicalPending")
pub fn client_program_model_physical_pending() -> @model.ModelPhysicalCallPoll {
  @model.PhysicalPending
}

///|
/// Missing quantities remain unknown; reservation maxima are not actual usage.
#export_name("clientProgramModelPhysicalUnknown")
pub fn client_program_model_physical_unknown() -> @model.ModelPhysicalCallPoll {
  @model.PhysicalUnknown({ input_tokens: None, output_tokens: None, })
}

///|
#export_name("clientProgramModelPhysicalSavedChat")
pub fn client_program_model_physical_saved_chat(
  response : @model.ModelPhysicalChatResponse,
) -> @model.ModelPhysicalCallPoll {
  @model.PhysicalChatResponse(response)
}

///|
/// Project actual raw port facts through the original call/registration Owner.
/// The trusted Store still must verify exact bytes before issuing any receipt.
#export_name("clientProgramObserveInferRawCapture")
pub fn client_program_observe_infer_raw_capture(
  call : @model.ModelPhysicalCall,
  registration : @publication_host.ClientModelRawCaptureRegistration,
  content_cid : String,
  byte_count : Int,
  http_status : Int,
  transport_eof : Bool,
  observed_at : String,
) -> Result[@model.ModelRawCaptureSave, @model.ModelRawCaptureSaveIssue] {
  @model.observe_model_raw_capture(
    call, registration, content_cid, byte_count, http_status, transport_eof, observed_at,
  )
}
