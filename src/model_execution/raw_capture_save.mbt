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
    model_slot_progress_owned(state, entry.progress) &&
    entry.progress.call is Some(original) &&
    physical_equal(original, call) &&
    state.prepared_call_set is Some(prepared) &&
    physical_equal(prepared, entry.prepared) &&
    entry.progress.slot == entry.slot &&
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
    call,
    registration,
    response: bound,
    saved: None,
    usage_reader: None,
    usage_result: None,
    usage_retired: false,
    usage_work: 0,
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
/// Borrow the policy-bound Raw accepted by the pending failure settlement.
/// The published Run still requires the original Store/Journal confirmation
/// and physical retirement. An independently captured or bare rejection
/// cannot supply this observation.
pub fn model_call_settlement_failure_raw(
  value : ModelCallSettlement,
) -> @publication.BoundModelRawResponse? {
  guard model_call_settlement_slot(value) is Some(slot) &&
    model_outcome_at(value.owner.state, slot) is Some(NoResponseFailure(_)) else {
    return None
  }
  model_call_settlement_complete_raw(value, slot)
}

///|
/// A dependent consumer can retain only the complete, saved Raw from the
/// same successful, still-unacknowledged physical attempt. Borrowing it
/// establishes neither Journal settlement nor eligibility of any consumer.
pub fn model_call_settlement_success_raw(
  value : ModelCallSettlement,
) -> @publication.BoundModelRawResponse? {
  guard model_call_settlement_slot(value) is Some(slot) &&
    model_outcome_at(value.owner.state, slot) is Some(Success(_)) &&
    model_call_settlement_complete_raw(value, slot) is Some(raw) else {
    return None
  }
  let (status, _, _) = @publication.model_raw_response_transport_facts(raw)
  if status >= 200 && status < 300 {
    Some(raw)
  } else {
    None
  }
}

///|
fn model_call_settlement_complete_raw(
  value : ModelCallSettlement,
  slot : Int,
) -> @publication.BoundModelRawResponse? {
  let state = value.owner.state
  guard value.progress.call is Some(call) &&
    !call.retired &&
    !call.settlement_acknowledged &&
    call.entry is Some(entry) &&
    entry.slot == slot &&
    entry.send_started &&
    physical_equal(entry.progress, value.progress) &&
    physical_equal(entry.prepared.owner, value.owner) &&
    state.attempts.get(slot) is Some(trace) &&
    physical_equal(trace, entry.trace) &&
    call.raw_capture is Some(raw) &&
    physical_equal(raw.call, call) &&
    raw.saved is Some(saved) &&
    physical_equal(saved.original, raw) else {
    return None
  }
  let accepted : ModelSavedRawReceipt = match call.terminal {
    Some(PhysicalChatResponse(response)) => response.saved_raw
    Some(PhysicalNativeResponse(response)) => response.raw.saved_raw
    Some(PhysicalSavedStructuredResponse(response)) => response.receipt
    Some(PhysicalMeasuredHttp(receipt, _, _, PhysicalRejected(_, _))) => receipt
    _ => return None
  }
  guard physical_equal(accepted, saved) else { return None }
  let (_, eof, _) = @publication.model_raw_response_transport_facts(
    raw.response,
  )
  if eof {
    Some(raw.response)
  } else {
    None
  }
}

///|
/// Before ACK, retain the exact failure Raw only for the strict path that
/// will stop on this original attempt.
pub fn model_call_settlement_retains_strict_failure(
  value : ModelCallSettlement,
) -> Bool {
  value.progress.phase is FailAfterSettlement &&
  model_call_settlement_failure_raw(value) is Some(_)
}

///|
/// Read the same held strict slot after its original ACK and physical return.
/// The caller must have retained the token before acknowledging it. A call's
/// slot loses its physical reference only after its cleanup and holding ACKs.
pub fn model_call_settlement_strict_failure_retired(
  value : ModelCallSettlement,
) -> Bool {
  value.progress.phase is FailAfterSettlement &&
  value.progress.slot == value.slot + 1 &&
  value.progress.settlement is None &&
  value.progress.call is None &&
  model_outcome_at(value.owner.state, value.slot) is Some(NoResponseFailure(_))
}

///|
/// Keep the trusted Store adapter on the exact compiled Run of this Call.
/// Neither a copied descriptor nor a matching public Run CID can replace it.
pub fn model_raw_capture_save_matches_run(
  value : ModelRawCaptureSave,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Bool {
  model_raw_capture_call_owned(value.call) &&
  value.call.entry is Some(entry) &&
  @publication_host.client_infer_dispatch_matches_run(
    entry.admission,
    compiled,
    definition,
  )
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
fn check_model_raw_capture_call_current(
  call : ModelPhysicalCall,
) -> Result[Unit, ModelRawCaptureSaveIssue] {
  if !model_raw_capture_call_owned(call) {
    return Err(ForeignCall)
  }
  let entry = call.entry.unwrap()
  if entry.prepared.owner.state.stop_requested || call.cancel_requested {
    return Err(Stopped)
  }
  Ok(())
}

///|
/// Recheck after every Store await and immediately before adopting a receipt.
/// A refusal does not erase physical persistence or release its retry custody.
pub fn model_raw_capture_save_current(
  value : ModelRawCaptureSave,
) -> Result[Unit, ModelRawCaptureSaveIssue] {
  match check_model_raw_capture_call_current(value.call) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    @publication_host.check_client_model_raw_capture_current(value.registration) {
    Err(issue) => return Err(Capture(issue))
    Ok(_) => ()
  }
  // The selection callback can stop or retire the original Call.
  check_model_raw_capture_call_current(value.call)
}

///|
/// The installed portable Store calls this inside its already-funded original
/// Read. The byte ceiling is a limit, not a reservation. Only the current
/// entered Call and its own admitted Raw can select the authenticated preimage.
/// Returning these bytes does not acknowledge persistence or authorize a send.
pub fn model_raw_capture_save_portable_input(
  value : ModelRawCaptureSave,
  call : ModelPhysicalCall,
  bytes : Bytes,
  plaintext_limit : Int,
) -> Result[(Bytes, Bytes), ModelRawCaptureSaveIssue] {
  guard physical_equal(value.call, call) &&
    call.raw_capture is Some(original) &&
    physical_equal(original, value) else {
    return Err(ForeignCall)
  }
  match model_raw_capture_save_current(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard call.raw_capture is Some(retained) && physical_equal(retained, value) else {
    return Err(ForeignCall)
  }
  let (semantic, _, descriptor, content, count) = @publication.model_raw_response_store_binding(
    value.response,
  )
  guard count == bytes.length() &&
    count <= 1048576 &&
    plaintext_limit > 0 &&
    plaintext_limit <= 1048576 else {
    return Err(ResponseLimit)
  }
  let descriptor_limit = plaintext_limit - 1 - 4 * ((count + 2) / 3)
  guard descriptor_limit > 0 &&
    @scalar.admit_utf8_length(descriptor, descriptor_limit) is Ok(_) else {
    return Err(ResponseLimit)
  }
  guard @publication.model_raw_response_store_plaintext(
      descriptor, content, count, bytes,
    )
    is Some(plaintext) &&
    @publication.private_evidence_aad("model_raw_response", semantic)
    is Some(aad) else {
    return Err(
      Evidence(
        @publication.RunEvidenceReferenceMismatch(
          "model_raw_response.content_cid",
        ),
      ),
    )
  }
  Ok((@utf8.encode(plaintext), aad))
}

///|
/// A trusted portable Store calls this after authenticating the actual
/// retained envelope under the existing Read, key and AAD. Only matching
/// plaintext from this exact Call is returned to its typed decoder.
pub fn acknowledge_portable_model_raw_readback(
  value : ModelRawCaptureSave,
  call : ModelPhysicalCall,
  authenticated : Bytes,
  plaintext_limit : Int,
) -> Result[(ModelSavedRawReceipt, Bytes), ModelRawCaptureSaveIssue] {
  guard physical_equal(value.call, call) &&
    call.raw_capture is Some(original) &&
    physical_equal(original, value) else {
    return Err(ForeignCall)
  }
  match model_raw_capture_save_current(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard authenticated.length() <= plaintext_limit &&
    plaintext_limit > 0 &&
    plaintext_limit <= 1048576 else {
    return Err(ResponseLimit)
  }
  guard @publication.read_model_raw_response_store_plaintext(
      value.response,
      authenticated,
      plaintext_limit,
    )
    is Some(bytes) else {
    return Err(
      Evidence(
        @publication.RunEvidenceReferenceMismatch(
          "model_raw_response.content_cid",
        ),
      ),
    )
  }
  acknowledge_saved_model_raw_capture(value).map(receipt => (receipt, bytes))
}

///|
/// Decode the bytes authenticated by the portable Store on the original
/// Read. Keeping decoding here prevents replacing the response text after
/// confirming the original Raw. Callers fund the plaintext and UTF-8 decode
/// before invocation and classify transfer/cleanup on the same Call.
pub fn portable_model_saved_chat_response(
  value : ModelRawCaptureSave,
  call : ModelPhysicalCall,
  authenticated : Bytes,
  plaintext_limit : Int,
) -> Result[
  (ModelSavedRawReceipt, ModelPhysicalCallPoll),
  ModelRawCaptureSaveIssue,
] {
  let (receipt, bytes) = match
    acknowledge_portable_model_raw_readback(
      value, call, authenticated, plaintext_limit,
    ) {
    Ok(original) => original
    Err(issue) => return Err(issue)
  }
  let (status, eof, _) = @publication.model_raw_response_transport_facts(
    value.response,
  )
  let usage : ModelPhysicalUsage = { input_tokens: None, output_tokens: None, }
  if !eof {
    return Ok((receipt, PhysicalUnknown(usage)))
  }
  if status < 200 || status >= 300 {
    return Ok((receipt, PhysicalRejected(ProviderError, usage)))
  }
  let body = @utf8.decode(bytes, ignore_bom=true) catch {
    _ => return Ok((receipt, PhysicalRejected(SchemaInvalid, usage)))
  }
  model_saved_raw_chat_response(receipt, body, None).map(response => {
    (receipt, PhysicalChatResponse(response))
  })
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
    failure_observation: None,
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
