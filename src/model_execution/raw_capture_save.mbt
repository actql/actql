///|
/// A view of the original entered physical call and its fixed raw cell. The
/// installed Store adapter retains this handle during persistence/reconciliation.
/// It is not another capture owner or a permit to enter/send a call again.
pub struct ModelRawCaptureSave {
  priv call : ModelPhysicalCall
  priv registration : @publication_host.ClientModelRawCaptureRegistration
  priv response : @publication.BoundModelRawResponse
  priv mut saved : ModelSavedRawReceipt?
  priv mut usage_reader : ModelRawUsageReader?
  priv mut usage_result : Result[Unit, ModelExecutionIssue]?
  priv mut usage_retired : Bool
  priv mut usage_work : Int
  priv mut usage_advancing : Bool
}

///|
/// Issued only after the trusted adapter has confirmed the exact original raw
/// bytes, descriptor and same-cell directory durability. This receipt observes
/// persistence, not answer validity, transport success or disclosure permission.
pub struct ModelSavedRawReceipt {
  priv original : ModelRawCaptureSave
}

///|
pub(all) enum ModelRawCaptureSaveIssue {
  ForeignCall
  Stopped
  Capture(@publication_host.ClientModelRawCaptureIssue)
  ResponseLimit
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
fn model_raw_capture_call_owned(call : ModelPhysicalCall) -> Bool {
  guard !call.retired && call.entry is Some(entry) && entry.send_started else {
    return false
  }
  let state = entry.prepared.owner.state
  guard !state.reclaimed &&
    state.pending_response is Some(original) &&
    physical_equal(original, call) &&
    state.prepared_call_set is Some(prepared) &&
    physical_equal(prepared, entry.prepared) &&
    state.next_slot == entry.slot &&
    state.attempts.get(entry.slot) is Some(trace) &&
    physical_equal(trace, entry.trace) &&
    state.reservations.get(entry.slot) is Some(reservation) &&
    @resources.reservation_open(reservation) else {
    return false
  }
  true
}

///|
/// Called before persistence, outside commit boundaries. The immutable
/// descriptor must match this call's original attempt, not a caller CID string.
pub fn prepare_model_raw_capture_save(
  call : ModelPhysicalCall,
  registration : @publication_host.ClientModelRawCaptureRegistration,
  response : @publication.RunEvidenceValue,
) -> Result[ModelRawCaptureSave, ModelRawCaptureSaveIssue] {
  if !model_raw_capture_call_owned(call) {
    return Err(ForeignCall)
  }
  let entry = call.entry.unwrap()
  let state = entry.prepared.owner.state
  if state.stop_requested || call.cancel_requested {
    return Err(Stopped)
  }
  guard entry.prepared.scope is Some(scope) &&
    @publication_host.client_model_raw_capture_matches(
      registration,
      entry.admission,
      scope,
    ) &&
    state.physical_plans.get(entry.slot) is Some(plan) &&
    plan.response_profile is Some(profile) else {
    return Err(ForeignCall)
  }
  let bound = match
    @publication_host.bind_client_model_raw_response(
      registration,
      response,
      entry.slot,
      entry.trace.attempt,
      entry.trace.authority,
    ) {
    Ok(bound) => bound
    Err(issue) => return Err(Capture(issue))
  }
  let (_, _, _, _, byte_count) = @publication.model_raw_response_store_binding(
    bound,
  )
  if @publication.model_raw_response_profile_cid(bound) !=
    @environment.model_response_profile_identity(profile) {
    return Err(ForeignCall)
  }
  if byte_count >
    @environment.model_response_profile_limits(profile).response_bytes ||
    byte_count.to_int64() > state.limits.max_response_bytes {
    return Err(ResponseLimit)
  }
  if call.raw_capture is Some(original) {
    return if physical_equal(original.registration, registration) &&
      @publication.run_evidence_value_identity(response) ==
      @publication.run_evidence_value_identity(
        @publication.model_raw_response_value(original.response),
      ) {
      Ok(original)
    } else {
      Err(ForeignCall)
    }
  }
  let value : ModelRawCaptureSave = {
    call, registration, response: bound, saved: None, usage_reader: None,
    usage_result: None, usage_retired: false, usage_work: 0,
    usage_advancing: false,
  }
  call.raw_capture = Some(value)
  Ok(value)
}

///|
/// Issue the closed descriptor from original call facts, never adapter-authored
/// evidence JSON. content_cid/count are actual physical port observations and
/// still require byte verification by the same Store before acknowledgement.
pub fn observe_model_raw_capture(
  call : ModelPhysicalCall,
  registration : @publication_host.ClientModelRawCaptureRegistration,
  content_cid : String,
  byte_count : Int,
  http_status : Int,
  transport_eof : Bool,
  observed_at : String,
) -> Result[ModelRawCaptureSave, ModelRawCaptureSaveIssue] {
  if !model_raw_capture_call_owned(call) {
    return Err(ForeignCall)
  }
  let entry = call.entry.unwrap()
  guard entry.prepared.scope is Some(scope) else { return Err(ForeignCall) }
  let response = match
    @publication.issue_model_raw_response(
      @publication_host.client_model_raw_capture_policy(registration),
      scope,
      entry.slot,
      entry.trace.attempt,
      entry.trace.authority,
      content_cid,
      byte_count,
      http_status,
      transport_eof,
      observed_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  prepare_model_raw_capture_save(call, registration, response)
}

///|
pub fn model_raw_capture_save_binding(
  value : ModelRawCaptureSave,
) -> @publication.BoundModelRawResponse {
  value.response
}

///|
/// Exact original dependency bodies for the trusted installed Store port.
pub fn model_raw_capture_save_originals(
  value : ModelRawCaptureSave,
) -> Array[@publication.CapturedEffectDependencyBody] {
  @publication.model_raw_capture_policy_originals(
    @publication_host.client_model_raw_capture_policy(value.registration),
  )
}

///|
/// Recheck after every Store await and immediately before adopting a receipt.
/// A refusal does not erase physical persistence or release its retry custody.
pub fn model_raw_capture_save_current(
  value : ModelRawCaptureSave,
) -> Result[Unit, ModelRawCaptureSaveIssue] {
  if !model_raw_capture_call_owned(value.call) {
    return Err(ForeignCall)
  }
  let entry = value.call.entry.unwrap()
  if entry.prepared.owner.state.stop_requested || value.call.cancel_requested {
    return Err(Stopped)
  }
  @publication_host.check_client_model_raw_capture_current(value.registration).map_err(issue => {
      Capture(issue)
    },
  )
}

///|
/// Private trusted Store port only. Unconfirmed/unknown/absent persistence
/// must not call this issuer. A matching semantic/content CID by itself cannot
/// substitute for the retained nominal original-call view.
pub fn acknowledge_saved_model_raw_capture(
  value : ModelRawCaptureSave,
) -> Result[ModelSavedRawReceipt, ModelRawCaptureSaveIssue] {
  match model_raw_capture_save_current(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.saved is Some(original) {
    return Ok(original)
  }
  let receipt : ModelSavedRawReceipt = { original: value, }
  value.saved = Some(receipt)
  Ok(receipt)
}

///|
/// Historical saved identity survives later permission changes while custody
/// is retained. It grants no present read, decode, capture or send permission.
pub fn model_saved_raw_receipt_matches(
  receipt : ModelSavedRawReceipt,
  call : ModelPhysicalCall,
  response : @publication.RunEvidenceValue,
) -> Bool {
  physical_equal(receipt.original.call, call) &&
  model_raw_capture_call_owned(call) &&
  @publication.run_evidence_value_identity(response) ==
  @publication.run_evidence_value_identity(
    @publication.model_raw_response_value(receipt.original.response),
  )
}

///|
/// Trusted installed decoder only: body is the fatal UTF-8 decoding of the
/// exact reconfirmed Store bytes. This factory binds transport observations
/// from the saved descriptor, not caller-supplied status/CID or completion.
/// It does not issue present read/disclosure, send or answer-validity rights.
pub fn model_saved_raw_chat_response(
  receipt : ModelSavedRawReceipt,
  body : String,
  provider_metadata : @canonical.CanonicalValue?,
) -> Result[ModelPhysicalChatResponse, ModelRawCaptureSaveIssue] {
  let original = receipt.original
  if !model_raw_capture_call_owned(original.call) {
    return Err(ForeignCall)
  }
  let (status, eof, observed_at) = @publication.model_raw_response_transport_facts(
    original.response,
  )
  Ok({
    body,
    status,
    transport_eof: eof,
    raw_response_artifact_cid: @publication.run_evidence_value_identity(
      @publication.model_raw_response_value(original.response),
    ),
    observed_at,
    provider_metadata,
    saved_raw: receipt,
  })
}

///|
fn model_chat_response_original(
  response : ModelPhysicalChatResponse,
  call : ModelPhysicalCall,
) -> Bool {
  model_saved_raw_receipt_matches(
    response.saved_raw,
    call,
    @publication.model_raw_response_value(response.saved_raw.original.response),
  )
}
