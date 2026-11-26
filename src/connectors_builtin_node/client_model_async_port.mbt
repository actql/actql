///|
// Select the existing registered precision DATA in this actual runtime.
// This proves neither native provider conformance, funding nor send authority.
#export_name("clientProgramInitialJevDecisionProfile")
pub fn client_program_initial_jev_decision_profile() -> @check_environment.DecisionProbabilityProfile {
  @check_environment.initial_jev_decision_profile()
}

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
// Physical DATA only, returned inside the original registered poll callback.
// Common admits the binding and issues its internal nominal observation; this
// function is not a bare ACK, Resource retirement or capability factory.
#export_name("clientProgramModelPhysicalIoObservation")
pub fn client_program_model_physical_io_observation(
  original : @model.ModelPhysicalCall,
  quiescent : Bool,
  inner : @model.ModelPhysicalCallPoll,
) -> @model.ModelPhysicalCallPoll {
  if quiescent {
    @model.PhysicalIoQuiescent(original, inner)
  } else {
    @model.PhysicalIoPending(original, inner)
  }
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
#export_name("clientProgramModelPhysicalSavedNativeDecision")
pub fn client_program_model_physical_saved_native_decision(
  response : @model.ModelPhysicalChatResponse,
  original : @model.NativeDecisionRequest,
  provider : @model.AdmittedModelProvider,
  probability : @check_environment.DecisionProbabilityProfile,
) -> Result[@model.ModelPhysicalCallPoll, @model.ModelExecutionIssue] {
  @model.model_physical_saved_native_response(
    response, original, provider, probability,
  )
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

///|
// Bind only the exact original configuration, Profile and admitted Provider.
#export_name("clientProgramBindAdmittedStructuredModelProvider")
pub fn client_program_bind_admitted_structured_model_provider(
  provider : @model.ModelProvider,
  original : @model.AdmittedModelProvider,
  binding : @publication.RunEvidenceValue,
  configuration : String,
  selector : String,
  model_id : String,
  adapter_kind : String,
  api_mode : String,
  profile : @check_environment.ModelResponseProfile,
  installation : @check_environment.ModelResponseProfileInstallation,
  adapter_supports : Bool,
  model_supports : Bool,
) -> Result[
  @model.AdmittedStructuredModelProvider,
  @model.StructuredModelCapabilityIssue,
] {
  match
    @model.register_structured_model_capability(
      provider,
      binding,
      configuration,
      {
        selector,
        model_id,
        adapter_kind,
        api_mode,
        endpoint: installation.endpoint,
      },
      profile,
      adapter_supports,
      model_supports,
    ) {
    Ok(capability) =>
      @model.bind_admitted_structured_model_provider(
        capability, original, installation,
      )
    Err(issue) => Err(issue)
  }
}

///|
// Initialization retains this exact capability before any original Request.
#export_name("clientProgramPrepareInstalledStructuredSdkCapability")
pub fn client_program_prepare_installed_structured_sdk_capability(
  provider : @model.ModelProvider,
  binding : @publication.RunEvidenceValue,
  configuration : String,
  selector : String,
  model_id : String,
  api_mode : String,
  endpoint : String,
  profile : @check_environment.ModelResponseProfile,
) -> Result[
  @model.StructuredModelCapability,
  @model.StructuredModelCapabilityIssue,
] {
  @model.register_structured_model_capability(
    provider,
    binding,
    configuration,
    { selector, model_id, adapter_kind: "ai-sdk", api_mode, endpoint, },
    profile,
    true,
    true,
  )
}

///|
#export_name("clientProgramAdmitInstalledStructuredSdkCapability")
pub fn client_program_admit_installed_structured_sdk_capability(
  capability : @model.StructuredModelCapability,
  original : @model.AdmittedModelProvider,
  installation : @check_environment.ModelResponseProfileInstallation,
) -> Result[
  @model.AdmittedStructuredModelProvider,
  @model.StructuredModelCapabilityIssue,
] {
  @model.bind_admitted_structured_model_provider(
    capability, original, installation,
  )
}

///|
#export_name("clientProgramAdmittedStructuredSdkRouteMatches")
pub fn client_program_admitted_structured_sdk_route_matches(
  admitted : @model.AdmittedStructuredModelProvider,
  selector : String,
  model_id : String,
  api_mode : String,
  endpoint : String,
) -> Bool {
  @model.admitted_structured_model_route_matches(admitted, {
    selector,
    model_id,
    adapter_kind: "ai-sdk",
    api_mode,
    endpoint,
  })
}

///|
#export_name("clientProgramStartAdmittedStructuredSdkProjection")
pub fn client_program_start_admitted_structured_sdk_projection(
  admitted : @model.AdmittedStructuredModelProvider,
  request : @model.ModelRequest,
  profile : @check_environment.ModelResponseProfile,
  installation : @check_environment.ModelResponseProfileInstallation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_frames : Int,
  max_work : Int,
) -> Result[@model.OpenAIChatProjection, @model.OpenAIChatProjectionIssue] {
  @model.start_admitted_structured_sdk_projection(
    admitted, request, profile, installation, max_bytes, max_nodes, max_depth, max_frames,
    max_work,
  )
}

///|
// The selected decoder transfers its original answer and optional reported
// usage from the same SDK read. Core meters and checks the observed quantities.
#export_name("clientProgramModelStructuredRequestPlan")
pub fn client_program_model_structured_request_plan(
  admitted : @model.AdmittedStructuredModelProvider,
  request : @model.ModelRequest,
  wire_bytes : Int64,
  tokens : Int64,
  cost_units : Int64,
  duration_ms : Int64,
  profile : @check_environment.ModelResponseProfile,
  installation : @check_environment.ModelResponseProfileInstallation,
  start : (@model.ModelCallEntry) -> @model.ModelPhysicalCall?,
  read_answer : (@model.ModelPhysicalCall, @model.ModelSavedRawReceipt, Bytes) -> (
    String?,
    String,
    Int64?,
    Int64?,
    String?,
    String?,
    String?,
    Bool?,
    String?,
    String?,
  )?,
) -> Result[@model.ModelPhysicalRequestPlan, @model.ModelExecutionIssue] {
  @model.bound_structured_model_async_request_plan(
    admitted,
    request,
    wire_bytes,
    { tokens, cost_units, duration_ms, },
    profile,
    installation,
    start,
    (call, receipt, bytes) => {
      read_answer(call, receipt, bytes).map(answer => {
        let (
          text,
          finish,
          input_tokens,
          output_tokens,
          model,
          request_id,
          reason,
          complete,
          metadata_name,
          metadata_value,
        ) = answer
        let answer : Result[String, @model.ModelProviderFailure] = match
          (finish, text) {
          ("stop", Some(body)) => Ok(body)
          ("length", _) => Err(Truncated)
          ("refusal", _) => Err(Refusal)
          ("safety" | "content-filter", _) => Err(SafetyRejected)
          _ => Err(SchemaInvalid)
        }
        {
          answer,
          observation: {
            origin: @publication.Reported,
            provider_model: model,
            provider_revision: None,
            provider_request_id: request_id,
            gateway_request_id: None,
            input_tokens,
            output_tokens,
            provider_finish_reason: reason,
            historical_finish_reason: None,
            response_profile_cid: Some(
              @check_environment.model_response_profile_identity(profile),
            ),
            response_complete: complete,
            raw_response_artifact_cid: None,
            provider_metadata: match (metadata_name, metadata_value) {
              (Some(name), Some(value)) =>
                @model.admit_saved_sdk_report_metadata(profile, name, value)
              _ => None
            },
            observed_at: "",
          },
        }
      })
    },
  )
}

///|
#export_name("clientProgramModelPhysicalSavedStructured")
pub fn client_program_model_physical_saved_structured(
  call : @model.ModelPhysicalCall,
  receipt : @model.ModelSavedRawReceipt,
  bytes : Bytes,
) -> Result[@model.ModelPhysicalCallPoll, @model.ModelExecutionIssue] {
  @model.model_physical_saved_structured_response(call, receipt, bytes)
}
