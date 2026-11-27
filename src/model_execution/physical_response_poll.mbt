///|
/// Installed codec observations, not issued completion or send authority.
/// The three completeness facts come from the verified physical decoder,
/// independently of optional provider metadata and SDK default values.
pub(all) struct ModelPhysicalResponse {
  value : @admitted.Value
  observation : @publication.ModelCaptureObservation
  transport_eof : Bool
  endpoint_complete : Bool
  answer_complete : Bool
}

///|
/// The installed codec's selected structured-answer text. This is not the raw
/// HTTP response artifact, and its completeness fields grant no send authority.
pub(all) struct ModelPhysicalEncodedResponse {
  body : String
  observation : @publication.ModelCaptureObservation
  transport_eof : Bool
  endpoint_complete : Bool
  answer_complete : Bool
}

///|
/// Original non-streaming Chat response custody. These are physical facts,
/// not a provider's selected answer, completion proof or dispatch authority.
/// The trusted installed caller decodes only the exact bytes reconfirmed by
/// the original Store. A CID string cannot construct this original-call view.
pub struct ModelPhysicalChatResponse {
  priv body : String
  priv status : Int
  priv transport_eof : Bool
  priv raw_response_artifact_cid : String
  priv observed_at : String
  priv provider_metadata : @canonical.CanonicalValue?
  priv saved_raw : ModelSavedRawReceipt
  priv mut failure_observation : @publication.ModelCaptureObservation?
}

///|
/// Partial usage survives a rejected response and an unknown remote result.
/// A missing observation remains None; reservation maxima are not actuals.
pub(all) struct ModelPhysicalUsage {
  input_tokens : Int64?
  output_tokens : Int64?
}

///|
pub(all) enum ModelPhysicalCallPoll {
  PhysicalPending
  PhysicalResponse(ModelPhysicalResponse)
  PhysicalEncodedResponse(ModelPhysicalEncodedResponse)
  PhysicalChatResponse(ModelPhysicalChatResponse)
  PhysicalNativeResponse(ModelPhysicalNativeResponse)
  PhysicalRejected(ModelProviderFailure, ModelPhysicalUsage)
  PhysicalUnknown(ModelPhysicalUsage)
  // Private physical DATA from the same registered call, not an ACK factory.
  // A conforming port wraps every poll, including a response before close.
  PhysicalIoPending(ModelPhysicalCall, ModelPhysicalCallPoll)
  PhysicalIoQuiescent(ModelPhysicalCall, ModelPhysicalCallPoll)
  PhysicalSavedStructuredResponse(ModelPhysicalSavedStructuredResponse)
  // Only the selected measured port can project this before terminal adoption.
  PhysicalMeasuredHttp(
    ModelSavedRawReceipt,
    Int64,
    Int64,
    ModelPhysicalCallPoll
  )
}

///|
// Registration captures the original binding before transport starts. A later
// current map entry cannot substitute another Plan or reservation. Common's
// private observed field only adopts this same record after checked poll DATA.
// All references and None domains require the original funded inventory.
priv struct ModelPhysicalCallBinding {
  entry : ModelCallEntry
  plan : ModelPhysicalRequestPlan
  reservation : @resources.Reservation
}

///|
/// A retained physical view of this Model Owner's original entered attempt.
/// Every callback/record/response backing must be funded before installation.
/// No new Run, journal, Ledger or Slot scheduler is represented by this view.
pub struct ModelPhysicalCall {
  mut entry : ModelCallEntry?
  mut poll : (() -> ModelPhysicalCallPoll)?
  mut cancel : (() -> Unit)?
  mut cleanup : ((Bool) -> Bool)?
  mut terminal : ModelPhysicalCallPoll?
  mut polling : Bool
  mut cancel_requested : Bool
  mut retired : Bool
  // Same child cleanup ACK cached through later Resource/holding retries.
  // This is NOT retirement of this Call, raw receipt or escaped views.
  priv mut cleanup_acknowledged : Bool
  mut settlement_acknowledged : Bool
  mut usage_result : Result[Unit, ModelExecutionIssue]?
  mut decoded_response : ModelPhysicalResponse?
  mut raw_capture : ModelRawCaptureSave?
  priv mut io_tracking : Bool
  priv mut original_binding : ModelPhysicalCallBinding?
  priv mut io_observation : ModelPhysicalCallBinding?
  priv mut poll_issue : ModelExecutionIssue?
}

///|
/// The original consumed Entry registers custody before the fixed transport
/// starts. Registration is not permission to send or proof of any transmission.
pub fn model_physical_call(
  entry : ModelCallEntry,
  prepared : ModelPreparedCallSet,
  poll : () -> ModelPhysicalCallPoll,
  cancel : () -> Unit,
  cleanup : (Bool) -> Bool,
) -> ModelPhysicalCall? {
  let state = prepared.owner.state
  guard physical_equal(entry.prepared, prepared) &&
    state.prepared_call_set is Some(original) &&
    physical_equal(original, prepared) &&
    model_slot_progress_owned(state, entry.progress) &&
    entry.progress.entry is Some(original) &&
    physical_equal(original, entry) &&
    !state.reclaimed &&
    entry.send_started &&
    entry.progress.phase is DispatchSlot &&
    entry.progress.slot == entry.slot &&
    state.attempts.get(entry.slot) is Some(trace) &&
    physical_equal(trace, entry.trace) &&
    state.physical_plans.get(entry.slot) is Some(plan) &&
    plan.invocation
    is (Asynchronous(_)
    | AsynchronousHttpChat(_, _)
    | AsynchronousMeasuredHttpChat(_, _)
    | AsynchronousSavedStructured(_, _, _)) &&
    state.reservations.get(entry.slot) is Some(reservation) &&
    @resources.reservation_open(reservation) else {
    return None
  }
  if entry.progress.call is Some(original) {
    return if original.entry is Some(owner) && physical_equal(owner, entry) {
      Some(original)
    } else {
      None
    }
  }
  let call : ModelPhysicalCall = {
    entry: Some(entry),
    poll: Some(poll),
    cancel: Some(cancel),
    cleanup: Some(cleanup),
    terminal: None,
    polling: false,
    cancel_requested: false,
    retired: false,
    cleanup_acknowledged: false,
    settlement_acknowledged: false,
    usage_result: None,
    decoded_response: None,
    raw_capture: None,
    io_tracking: false,
    original_binding: Some({ entry, plan, reservation, }),
    io_observation: None,
    poll_issue: None,
  }
  entry.progress.call = Some(call)
  Some(call)
}

///|
fn poll_model_physical_call(
  call : ModelPhysicalCall,
) -> Result[ModelPhysicalCallPoll?, ModelExecutionIssue] {
  if call.retired || call.polling {
    return Ok(None)
  }
  if call.terminal is Some(observed) &&
    (!call.io_tracking || call.io_observation is Some(_)) {
    return Ok(Some(observed))
  }
  guard call.poll is Some(poll) else { return Ok(call.terminal) }
  call.polling = true
  let observed = poll()
  call.polling = false
  let inner = match observed {
    PhysicalIoPending(original, inner) | PhysicalIoQuiescent(original, inner) => {
      if inner is (PhysicalIoPending(_, _) | PhysicalIoQuiescent(_, _)) ||
        !physical_equal(original, call) {
        return Err(RequestIdentity)
      }
      guard call.entry is Some(entry) &&
        call.original_binding is Some(binding) &&
        physical_equal(binding.entry, entry) else {
        return Err(RequestIdentity)
      }
      let state = entry.prepared.owner.state
      guard model_slot_progress_owned(state, entry.progress) &&
        entry.progress.call is Some(current) &&
        physical_equal(current, call) &&
        state.prepared_call_set is Some(prepared) &&
        physical_equal(prepared, entry.prepared) &&
        state.attempts.get(entry.slot) is Some(trace) &&
        physical_equal(trace, entry.trace) &&
        state.physical_plans.get(entry.slot) is Some(plan) &&
        physical_equal(plan, binding.plan) &&
        plan.invocation
        is (Asynchronous(_)
        | AsynchronousHttpChat(_, _)
        | AsynchronousMeasuredHttpChat(_, _)
        | AsynchronousSavedStructured(_, _, _)) &&
        state.reservations.get(entry.slot) is Some(reservation) &&
        physical_equal(reservation, binding.reservation) &&
        @resources.reservation_open(reservation) &&
        entry.send_started &&
        !state.reclaimed else {
        return Err(RequestIdentity)
      }
      if call.io_observation is Some(previous) {
        if !physical_equal(previous.entry, entry) ||
          !physical_equal(previous.plan, plan) ||
          !physical_equal(previous.reservation, reservation) {
          return Err(RequestIdentity)
        }
      }
      call.io_tracking = true
      if observed is PhysicalIoQuiescent(_, _) && call.io_observation is None {
        call.io_observation = Some(binding)
      }
      if call.io_observation is Some(_) {
        match retire_model_slot_io_after_call_observation(state, call) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
      }
      inner
    }
    original => original
  }
  // Once admitted, the original response/Unknown is immutable. Subsequent
  // polls only progress that same call's I/O observation, never another answer.
  if call.terminal is None {
    match inner {
      PhysicalPending => ()
      PhysicalMeasuredHttp(receipt, uploaded, downloaded, result) as measured =>
        match
          settle_model_http_observation(
            call, receipt, uploaded, downloaded, result,
          ) {
          // A bare rejection has no authenticated Raw. Keep the original
          // measured carrier when this rejection passed receipt admission.
          Ok(PhysicalRejected(_, _)) => call.terminal = Some(measured)
          Ok(settled) => call.terminal = Some(settled)
          Err(issue) => return Err(issue)
        }
      _ => call.terminal = Some(inner)
    }
  }
  if call.terminal is Some(_) &&
    (!call.io_tracking || call.io_observation is Some(_)) {
    call.poll = None
  }
  Ok(
    match call.terminal {
      Some(original) => Some(original)
      None => Some(inner)
    },
  )
}

///|
/// Classify an already rejected complete HTTP response. For 2xx, the
/// caller has independently established that its body cannot be decoded.
/// A status supplies neither a transport nor a settlement proof.
pub fn model_http_rejected_response_failure(
  status : Int,
) -> ModelProviderFailure {
  if status == 429 {
    RateLimit
  } else if status >= 200 && status < 300 {
    SchemaInvalid
  } else {
    ProviderError
  }
}

///|
// Both envelope carriers use this only after authenticating a complete Raw
// response. A syntax/shape failure supplied no decodable usage.
fn accept_saved_model_http_rejection_without_usage(
  state : ModelState,
  call : ModelPhysicalCall,
  status : Int,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  let unreported = PhysicalUnknown({ input_tokens: None, output_tokens: None, })
  if observe_model_physical_usage(state, call, unreported) is Err(issue) {
    return @bounded.Failed(issue, 1, 1)
  }
  match retire_model_raw_usage_child(call) {
    Err(issue) => return @bounded.Failed(issue, 1, 1)
    Ok(_) => ()
  }
  state.progress.observing_response = false
  accept_failed_model_slot(state, model_http_rejected_response_failure(status))
}

///|
fn settle_model_http_observation(
  call : ModelPhysicalCall,
  receipt : ModelSavedRawReceipt,
  uploaded : Int64,
  downloaded : Int64,
  result : ModelPhysicalCallPoll,
) -> Result[ModelPhysicalCallPoll, ModelExecutionIssue] {
  let raw = receipt.original
  let (status, eof, _) = @publication.model_raw_response_transport_facts(
    raw.response,
  )
  let matching_outcome = match result {
    PhysicalChatResponse(response) =>
      physical_equal(response.saved_raw, receipt)
    PhysicalRejected(failure, usage) =>
      eof &&
      failure == model_http_rejected_response_failure(status) &&
      usage.input_tokens is None &&
      usage.output_tokens is None &&
      raw.usage_reader is None &&
      !raw.usage_advancing
    _ => false
  }
  // A foreign view cannot publish its answer or redeem the entered ceiling.
  guard call.original_binding is Some(binding) &&
    call.io_observation is Some(observed) &&
    physical_equal(observed, binding) &&
    binding.plan.invocation is AsynchronousMeasuredHttpChat(request, _) &&
    physical_equal(raw.call, call) &&
    call.raw_capture is Some(original) &&
    physical_equal(original, raw) &&
    raw.saved is Some(saved) &&
    physical_equal(saved, receipt) &&
    model_raw_capture_call_owned(call) &&
    matching_outcome else {
    return Ok(PhysicalUnknown({ input_tokens: None, output_tokens: None, }))
  }
  if result is PhysicalRejected(_, _) {
    // The authenticated bytes did not produce a UTF-8 decoder child or
    // usage facts. Retire that exact empty reader obligation before the
    // caller can obtain the original Attempt evidence for settlement.
    match retire_model_raw_usage_child(call) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  let state = binding.entry.prepared.owner.state
  let request_bytes = request.body.length().to_int64()
  let (_, _, _, _, raw_bytes) = @publication.model_raw_response_store_binding(
    raw.response,
  )
  if eof &&
    status >= 200 &&
    status <= 599 &&
    uploaded >= 0L &&
    uploaded <= request_bytes &&
    request_bytes <= state.limits.max_request_bytes &&
    (status >= 300 || uploaded == request_bytes) &&
    downloaded >= 0L &&
    downloaded == raw_bytes.to_int64() &&
    downloaded <= state.limits.max_response_bytes {
    match
      @resources.settle_entered_transfer(
        state.ledger,
        binding.reservation,
        state.limits.max_request_bytes + state.limits.max_response_bytes,
        Some(uploaded + downloaded),
      ) {
      Err(issue) => return Err(Ledger(issue))
      Ok(_) => ()
    }
  }
  // An incomplete byte measurement does not change the confirmed Raw
  // outcome. Its original ceiling stays in custody until retirement.
  Ok(result)
}

///|
fn cancel_model_physical_call(call : ModelPhysicalCall) -> Unit {
  if !call.retired && !call.cleanup_acknowledged && !call.cancel_requested {
    call.cancel_requested = true
    if call.cancel is Some(cancel) {
      cancel()
    }
    call.cancel = None
  }
}

///|
// This path also runs after the bounded kernel has stopped. A terminal poll
// does not prove local cleanup, response persistence or remote cancellation.
fn cleanup_model_physical_call(state : ModelState) -> Bool {
  guard state.progress.call is Some(call) else { return true }
  if call.polling || (call.raw_capture is Some(raw) && raw.usage_advancing) {
    return false
  }
  if !call.cleanup_acknowledged {
    if !call.settlement_acknowledged {
      cancel_model_physical_call(call)
    }
    guard poll_model_physical_call(call) is Ok(Some(observed)) &&
      !(observed is PhysicalPending) else {
      return false
    }
    // Keep reported quantities even if the session cannot advance again.
    match observe_model_physical_usage(state, call, observed) {
      Err(_) | Ok(_) => ()
    }
    // A port that has opted into separate I/O observation cannot retire all
    // holding through a cleanup Bool while that original close is unconfirmed.
    if call.io_tracking && call.io_observation is None {
      return false
    }
    guard call.cleanup is Some(cleanup) else { return false }
    call.polling = true
    let released = cleanup(call.settlement_acknowledged)
    call.polling = false
    if !released {
      return false
    }
    // Actual physical cleanup retires the original accounting child, retaining
    // any usage already scanned. It cannot turn Unknown into a response.
    retire_model_raw_usage_child(call) |> ignore
    // Remember this original physical ACK even if later Resource retirement
    // is fenced. Retry the same remaining duty, never re-clean the SDK child.
    call.cleanup_acknowledged = true
  }
  if !retire_model_slot_io_holding(state, call) {
    return false
  }
  if !call.retired {
    call.cleanup = None
    call.cancel = None
    call.poll = None
    call.entry = None
    call.terminal = None
    call.decoded_response = None
    if call.raw_capture is Some(raw) {
      // The receipt keeps its original Raw. Drop only Raw's cached reverse
      // edge, after physical and holding retirement, so its current callbacks
      // do not retain the Native Work and Store after the last consumer.
      raw.saved = None
    }
    call.raw_capture = None
    call.io_observation = None
    call.original_binding = None
    call.io_tracking = false
    call.poll_issue = None
    call.retired = true
  }
  state.progress.call = None
  true
}

///|
fn observe_model_physical_usage(
  state : ModelState,
  call : ModelPhysicalCall,
  observed : ModelPhysicalCallPoll,
) -> Result[Unit, ModelExecutionIssue] {
  // A structured capability must not publish through the legacy response
  // carriers, even if the installed adapter returns such a poll.
  if model_call_requires_structured_receipt(call) &&
    observed
    is (PhysicalResponse(_)
    | PhysicalEncodedResponse(_)
    | PhysicalChatResponse(_)
    | PhysicalNativeResponse(_)) {
    return Err(OutputIdentity)
  }
  // Raw usage has not been decoded yet. Do not cache unknown quantities and
  // thereby discard actual usage discovered by the original Common child.
  if observed is (PhysicalChatResponse(_) | PhysicalNativeResponse(_)) {
    return call.usage_result.unwrap_or(Ok(()))
  }
  if call.usage_result is Some(original) {
    return original
  }
  let result = observe_original_model_physical_usage(state, call, observed)
  if !(observed is PhysicalPending) {
    call.usage_result = Some(result)
    // This path has no Chat RAW usage reader. Seal the original custody's
    // accounting observation before the journal asks for the attempt proof.
    if model_call_requires_structured_receipt(call) {
      retire_model_raw_usage_child(call) |> ignore
    }
  }
  result
}

///|
fn observe_original_model_physical_usage(
  state : ModelState,
  call : ModelPhysicalCall,
  observed : ModelPhysicalCallPoll,
) -> Result[Unit, ModelExecutionIssue] {
  guard call.entry is Some(entry) &&
    state.attempts.get(entry.slot) is Some(trace) &&
    physical_equal(trace, entry.trace) else {
    return Err(RequestIdentity)
  }
  let usage = match observed {
    PhysicalResponse(response) =>
      {
        input_tokens: response.observation.input_tokens,
        output_tokens: response.observation.output_tokens,
      }
    PhysicalEncodedResponse(response) =>
      {
        input_tokens: response.observation.input_tokens,
        output_tokens: response.observation.output_tokens,
      }
    PhysicalSavedStructuredResponse(response) => {
      if !model_saved_structured_response_original(response, call) {
        return Err(RequestIdentity)
      }
      {
        input_tokens: response.observation.bind(value => value.input_tokens),
        output_tokens: response.observation.bind(value => value.output_tokens),
      }
    }
    PhysicalRejected(_, usage)
    | PhysicalMeasuredHttp(_, _, _, PhysicalRejected(_, usage))
    | PhysicalUnknown(usage) => usage
    PhysicalPending
    | PhysicalChatResponse(_)
    | PhysicalNativeResponse(_)
    | PhysicalIoPending(_, _)
    | PhysicalMeasuredHttp(_, _, _, _)
    | PhysicalIoQuiescent(_, _) => return Ok(())
  }
  if !valid_model_optional_tokens(usage.input_tokens) ||
    !valid_model_optional_tokens(usage.output_tokens) {
    return Err(OutputIdentity)
  }
  trace.input_tokens = usage.input_tokens
  trace.output_tokens = usage.output_tokens
  if state.quantity_capacity is Some(_) &&
    usage.input_tokens is Some(input) &&
    usage.output_tokens is Some(output) {
    if input > 9223372036854775807L - output {
      return Err(OutputIdentity)
    }
    guard state.reservations.get(entry.slot) is Some(reservation) else {
      return Err(RequestIdentity)
    }
    @resources.observe_quantities(
      state.ledger,
      reservation,
      tokens=Some(input + output),
    ).map_err(issue => Ledger(issue))
  } else {
    Ok(())
  }
}

///|
fn advance_model_physical_response(
  state : ModelState,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  if state.progress.call is Some(call) && call.poll_issue is Some(issue) {
    // A malformed physical carrier stops through the existing bounded Owner,
    // retaining its original call for cleanup instead of escaping a live child.
    return @bounded.Failed(issue, 1, 1)
  }
  guard state.progress.call is Some(call) &&
    call.entry is Some(entry) &&
    entry.slot == state.progress.slot &&
    call.terminal is Some(observed) &&
    state.requests.get(state.progress.slot) is Some(prepared) else {
    return @bounded.Failed(RequestIdentity, 1, 1)
  }
  match observe_model_physical_usage(state, call, observed) {
    Err(issue) => return @bounded.Failed(issue, 1, 1)
    Ok(_) => ()
  }
  match observed {
    PhysicalPending | PhysicalIoPending(_, _) | PhysicalIoQuiescent(_, _) =>
      @bounded.Failed(RequestIdentity, 1, 1)
    PhysicalUnknown(_) => {
      state.progress.observing_response = false
      adopt_model_outcome(state, UnresolvedUnknown)
      @bounded.Failed(UnknownCalls, 1, 1)
    }
    PhysicalRejected(failure, _)
    | PhysicalMeasuredHttp(_, _, _, PhysicalRejected(failure, _)) => {
      state.progress.observing_response = false
      observe_model_physical(state, InvokeFailed)
      if state.stop_requested || failure == Cancelled {
        @bounded.Stopped(@bounded.Cancelled, 1, 1)
      } else {
        accept_failed_model_slot(state, failure)
      }
    }
    PhysicalMeasuredHttp(_, _, _, _) => @bounded.Failed(RequestIdentity, 1, 1)
    PhysicalResponse(response) => {
      observe_model_physical(state, InvokeReturned)
      begin_reported_model_response(state, prepared, response, reader)
    }
    PhysicalEncodedResponse(response) => {
      observe_model_physical(state, InvokeReturned)
      begin_encoded_model_response(state, prepared, response, reader)
    }
    PhysicalChatResponse(response) => {
      observe_model_physical(state, InvokeReturned)
      begin_chat_model_response(state, prepared, response, reader)
    }
    PhysicalNativeResponse(response) => {
      observe_model_physical(state, InvokeReturned)
      begin_native_model_response(state, prepared, response, reader)
    }
    PhysicalSavedStructuredResponse(response) =>
      match response.result {
        Err(failure) => accept_structured_model_failure(state, failure)
        Ok(encoded) => {
          observe_model_physical(state, InvokeReturned)
          begin_encoded_model_response(state, prepared, encoded, reader)
        }
      }
  }
}

///|
fn accept_structured_model_failure(
  state : ModelState,
  failure : ModelProviderFailure,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  state.progress.observing_response = false
  observe_model_physical(state, InvokeFailed)
  if state.stop_requested {
    return @bounded.Stopped(@bounded.Cancelled, 1, 1)
  }
  accept_failed_model_slot(state, failure)
}
