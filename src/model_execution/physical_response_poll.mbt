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
  PhysicalRejected(ModelProviderFailure, ModelPhysicalUsage)
  PhysicalUnknown(ModelPhysicalUsage)
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
  mut settlement_acknowledged : Bool
  mut usage_result : Result[Unit, ModelExecutionIssue]?
  mut decoded_response : ModelPhysicalResponse?
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
    state.entering is Some(original) &&
    physical_equal(original, entry) &&
    !state.reclaimed &&
    entry.send_started &&
    state.phase is DispatchSlot &&
    state.next_slot == entry.slot &&
    state.attempts.get(entry.slot) is Some(trace) &&
    physical_equal(trace, entry.trace) &&
    state.physical_plans.get(entry.slot) is Some(plan) &&
    plan.invocation is Asynchronous(_) &&
    state.reservations.get(entry.slot) is Some(reservation) &&
    @resources.reservation_open(reservation) else {
    return None
  }
  if state.pending_response is Some(original) {
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
    settlement_acknowledged: false,
    usage_result: None,
    decoded_response: None,
  }
  state.pending_response = Some(call)
  Some(call)
}

///|
fn poll_model_physical_call(call : ModelPhysicalCall) -> ModelPhysicalCallPoll? {
  if call.retired || call.polling {
    return None
  }
  if call.terminal is Some(observed) {
    return Some(observed)
  }
  guard call.poll is Some(poll) else { return None }
  call.polling = true
  let observed = poll()
  call.polling = false
  match observed {
    PhysicalPending => ()
    _ => {
      call.terminal = Some(observed)
      call.poll = None
    }
  }
  Some(observed)
}

///|
fn cancel_model_physical_call(call : ModelPhysicalCall) -> Unit {
  if !call.retired && !call.cancel_requested {
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
  guard state.pending_response is Some(call) else { return true }
  if call.polling {
    return false
  }
  if !call.retired {
    if !call.settlement_acknowledged {
      cancel_model_physical_call(call)
    }
    guard poll_model_physical_call(call) is Some(observed) &&
      !(observed is PhysicalPending) else {
      return false
    }
    // Keep reported quantities even if the session cannot advance again.
    match observe_model_physical_usage(state, call, observed) {
      Err(_) | Ok(_) => ()
    }
    guard call.cleanup is Some(cleanup) else { return false }
    call.polling = true
    let released = cleanup(call.settlement_acknowledged)
    call.polling = false
    if !released {
      return false
    }
    call.cleanup = None
    call.cancel = None
    call.poll = None
    call.entry = None
    call.terminal = None
    call.decoded_response = None
    call.retired = true
  }
  state.pending_response = None
  true
}

///|
fn observe_model_physical_usage(
  state : ModelState,
  call : ModelPhysicalCall,
  observed : ModelPhysicalCallPoll,
) -> Result[Unit, ModelExecutionIssue] {
  // Raw usage has not been decoded yet. Do not cache unknown quantities and
  // thereby discard actual usage discovered by the original Common child.
  if observed is PhysicalChatResponse(_) {
    return call.usage_result.unwrap_or(Ok(()))
  }
  if call.usage_result is Some(original) {
    return original
  }
  let result = observe_original_model_physical_usage(state, call, observed)
  if !(observed is PhysicalPending) {
    call.usage_result = Some(result)
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
    PhysicalRejected(_, usage) | PhysicalUnknown(usage) => usage
    PhysicalPending | PhysicalChatResponse(_) => return Ok(())
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
  guard state.pending_response is Some(call) &&
    call.entry is Some(entry) &&
    entry.slot == state.next_slot &&
    call.terminal is Some(observed) &&
    state.requests.get(state.next_slot) is Some(prepared) else {
    return @bounded.Failed(RequestIdentity, 1, 1)
  }
  match observe_model_physical_usage(state, call, observed) {
    Err(issue) => return @bounded.Failed(issue, 1, 1)
    Ok(_) => ()
  }
  match observed {
    PhysicalPending => @bounded.Failed(RequestIdentity, 1, 1)
    PhysicalUnknown(_) => {
      state.observing_response = false
      state.outcomes.push(UnresolvedUnknown)
      @bounded.Failed(UnknownCalls, 1, 1)
    }
    PhysicalRejected(failure, _) => {
      state.observing_response = false
      observe_model_physical(state, InvokeFailed)
      if state.stop_requested || failure == Cancelled {
        @bounded.Stopped(@bounded.Cancelled, 1, 1)
      } else {
        accept_failed_model_slot(state, failure)
      }
    }
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
  }
}
