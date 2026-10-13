///|
priv enum ModelRawUsageReader {
  ChatUsage(ChatEnvelopeDecode)
  NativeUsage(NativeEnvelopeDecode)
}

///|
fn model_raw_usage_facts(reader : ModelRawUsageReader) -> ChatEnvelopeFacts? {
  match reader {
    ChatUsage(child) => child.facts
    NativeUsage(child) => child.facts
  }
}

///|
fn cancel_model_raw_usage_reader(reader : ModelRawUsageReader) -> Unit {
  match reader {
    ChatUsage(child) => cancel_chat_envelope_decode(child)
    NativeUsage(child) => cancel_native_envelope_decode(child)
  }
}

///|
fn advance_model_raw_usage_reader(
  reader : ModelRawUsageReader,
) -> Result[ChatEnvelopeFacts?, ModelExecutionIssue] {
  match reader {
    ChatUsage(child) => advance_chat_envelope_decode(child)
    NativeUsage(child) =>
      advance_native_envelope_decode(child).map(root => {
        match root {
          None => None
          Some(_) => child.facts
        }
      })
  }
}

///|
// Merge actual observations only. The terminal poll/result and immutable
// evidence are not replaced by a later cleanup observation.
fn retain_reconciled_raw_usage(
  call : ModelPhysicalCall,
  facts : ChatEnvelopeFacts,
) -> Result[Unit, ModelExecutionIssue] {
  guard call.entry is Some(entry) else { return Err(RequestIdentity) }
  let state = entry.prepared.owner.state
  let trace = entry.trace
  if trace.evidence is Some(_) {
    return Err(OutputIdentity)
  }
  if call.usage_result is Some(Err(issue)) {
    return Err(issue)
  }
  for
    (old, actual) in [
      (trace.input_tokens, facts.input_tokens),
      (trace.output_tokens, facts.output_tokens),
    ] {
    if old is Some(old) && actual is Some(actual) && old != actual {
      return Err(OutputIdentity)
    }
  }
  // Both actual quantities have already settled this original reservation.
  // Reconfirmation or a repeated reader call must not charge them again.
  if trace.input_tokens is Some(_) && trace.output_tokens is Some(_) {
    return Ok(())
  }
  let usage : ModelPhysicalUsage = {
    input_tokens: match trace.input_tokens {
      Some(_) => trace.input_tokens
      None => facts.input_tokens
    },
    output_tokens: match trace.output_tokens {
      Some(_) => trace.output_tokens
      None => facts.output_tokens
    },
  }
  observe_original_model_physical_usage(state, call, PhysicalUnknown(usage))
}

///|
fn retire_model_raw_usage_child(
  call : ModelPhysicalCall,
) -> Result[Unit, ModelExecutionIssue] {
  guard call.raw_capture is Some(raw) else { return Ok(()) }
  if raw.usage_retired {
    return raw.usage_result.unwrap_or(Ok(()))
  }
  let result = if raw.usage_reader is Some(reader) &&
    model_raw_usage_facts(reader) is Some(facts) {
    retain_reconciled_raw_usage(call, facts)
  } else {
    Ok(())
  }
  if raw.usage_reader is Some(reader) {
    cancel_model_raw_usage_reader(reader)
  }
  raw.usage_reader = None
  raw.usage_retired = true
  raw.usage_result = Some(result)
  result
}

///|
/// Cleanup-only reader of the nominal original saved raw response. Reuse the
/// same bounded envelope codec and original Model work ceiling. No response,
/// authorization, phase, retry, or replacement accounting evidence is issued.
pub fn advance_model_reconciled_raw_usage(
  call : ModelPhysicalCall,
  response : ModelPhysicalChatResponse,
  quantum : Int,
) -> Result[(Bool, Int64), ModelExecutionIssue] {
  if quantum < 1 {
    return Err(InvalidLimits)
  }
  guard model_chat_response_original(response, call) &&
    call.raw_capture is Some(raw) &&
    physical_equal(raw, response.saved_raw.original) &&
    call.entry is Some(entry) else {
    return Err(RequestIdentity)
  }
  let stopped_original = match call.terminal {
    Some(PhysicalUnknown(_) | PhysicalRejected(_, _)) => true
    Some(PhysicalChatResponse(original)) =>
      physical_equal(original, response) &&
      @bounded.session_stopped(entry.prepared.owner.session)
    Some(PhysicalNativeResponse(native)) =>
      model_native_response_original(native, call) &&
      physical_equal(native.raw, response) &&
      @bounded.session_stopped(entry.prepared.owner.session)
    _ => false
  }
  // An incomplete/failed native decode may retain a nominal saved prefix.
  // Only its stopped original execution may reconcile usage; never run two
  // CPU readers concurrently or replace its immutable physical terminal.
  if !stopped_original {
    return Err(RequestIdentity)
  }
  if raw.usage_retired {
    return raw.usage_result
      .unwrap_or(Ok(()))
      .map(_ => (true, raw.usage_work.to_int64()))
  }
  if raw.usage_advancing {
    return Err(Session(@bounded.ConcurrentResume))
  }
  raw.usage_advancing = true
  let result = advance_reconciled_raw_usage_owned(
    call, response, raw, entry, quantum,
  )
  raw.usage_advancing = false
  result
}

///|
fn advance_reconciled_raw_usage_owned(
  call : ModelPhysicalCall,
  response : ModelPhysicalChatResponse,
  raw : ModelRawCaptureSave,
  entry : ModelCallEntry,
  quantum : Int,
) -> Result[(Bool, Int64), ModelExecutionIssue] {
  let state = entry.prepared.owner.state
  if entry.trace.evidence is Some(_) {
    return Err(OutputIdentity)
  }
  for _ in 0..<quantum {
    // Keep scanned partials before a stop, permission/clock failure, work
    // exhaustion or codec error can retire the child.
    if raw.usage_reader is Some(reader) &&
      model_raw_usage_facts(reader) is Some(facts) {
      match retain_reconciled_raw_usage(call, facts) {
        Err(issue) => return finish_reconciled_raw_usage(call, raw, Err(issue))
        Ok(_) => ()
      }
    }
    match model_raw_capture_save_current(raw) {
      Err(Stopped) =>
        return finish_reconciled_raw_usage(call, raw, Err(Cancelled))
      Err(Capture(Expired)) =>
        return finish_reconciled_raw_usage(call, raw, Err(Deadline))
      Err(Capture(Authorization(issue))) =>
        return finish_reconciled_raw_usage(
          call,
          raw,
          Err(Authorization(@publication_host.Authorization(issue))),
        )
      Err(_) =>
        return finish_reconciled_raw_usage(call, raw, Err(RequestIdentity))
      Ok(_) => ()
    }
    if !model_chat_response_original(response, call) {
      return finish_reconciled_raw_usage(call, raw, Err(RequestIdentity))
    }
    if state.stop_requested || call.cancel_requested {
      return finish_reconciled_raw_usage(call, raw, Err(Cancelled))
    }
    if state.work >= state.limits.max_work {
      return finish_reconciled_raw_usage(call, raw, Err(WorkLimit))
    }
    state.work += 1
    raw.usage_work += 1
    entry.trace.work = state.work
    if raw.usage_reader is None {
      guard state.physical_plans.get(entry.slot) is Some(plan) &&
        plan.response_profile is Some(profile) else {
        return finish_reconciled_raw_usage(call, raw, Err(RequestIdentity))
      }
      let limits = @environment.model_response_profile_limits(profile)
      let child = if @environment.model_response_profile_completion_basis(
          profile,
        ) ==
        "native_decision" {
        start_native_envelope_decode(response.body, limits).map(child => {
          NativeUsage(child)
        })
      } else {
        start_chat_envelope_decode(response.body, limits).map(child => {
          ChatUsage(child)
        })
      }
      match child {
        Err(issue) => return finish_reconciled_raw_usage(call, raw, Err(issue))
        Ok(reader) => raw.usage_reader = Some(reader)
      }
    } else {
      match advance_model_raw_usage_reader(raw.usage_reader.unwrap()) {
        Err(issue) => return finish_reconciled_raw_usage(call, raw, Err(issue))
        Ok(None) => ()
        Ok(Some(facts)) => {
          let result = retain_reconciled_raw_usage(call, facts)
          return finish_reconciled_raw_usage(call, raw, result)
        }
      }
    }
  }
  Ok((false, raw.usage_work.to_int64()))
}

///|
fn finish_reconciled_raw_usage(
  call : ModelPhysicalCall,
  raw : ModelRawCaptureSave,
  result : Result[Unit, ModelExecutionIssue],
) -> Result[(Bool, Int64), ModelExecutionIssue] {
  let retained = retire_model_raw_usage_child(call)
  let result = match result {
    Err(issue) => Err(issue)
    Ok(_) => retained
  }
  raw.usage_result = Some(result)
  // A stopped native response can precede the ordinary usage observation.
  // Retiring its original reader seals that observation, not the Unknown
  // outcome. Preserve any already established call result unchanged.
  if call.usage_result is None {
    call.usage_result = Some(result)
  }
  result.map(_ => (true, raw.usage_work.to_int64()))
}

///|
/// Observe only this stopped execution's original raw accounting child before
/// freezing its attempt proof. The optional issue is the retired reader's
/// observation, not a replacement Model outcome or a cleanup/send grant.
pub fn advance_model_stopped_raw_usage(
  execution : ModelExecution,
  slot : Int,
  quantum : Int,
) -> Result[(Bool, Int64, ModelExecutionIssue?), ModelExecutionIssue] {
  if quantum < 1 {
    return Err(InvalidLimits)
  }
  if execution.advancing {
    return Err(Session(@bounded.ConcurrentResume))
  }
  if check_model_original_resources_mutable(execution.state) is Err(issue) {
    return Err(issue)
  }
  guard !execution.state.reclaimed &&
    !execution.state.accepted &&
    @bounded.session_stopped(execution.session) &&
    execution.state.attempts.get(slot) is Some(_) else {
    return Err(OutputIdentity)
  }
  execution.advancing = true
  let result = advance_model_stopped_raw_usage_owned(execution, slot, quantum)
  execution.advancing = false
  result
}

///|
fn advance_model_stopped_raw_usage_owned(
  execution : ModelExecution,
  slot : Int,
  quantum : Int,
) -> Result[(Bool, Int64, ModelExecutionIssue?), ModelExecutionIssue] {
  let state = execution.state
  guard state.pending_response is Some(call) &&
    call.entry is Some(entry) &&
    entry.slot == slot else {
    // A previous attempt has no pending raw child. This is zero additional
    // reader work, never an observation of zero tokens or physical cleanup.
    return Ok((true, 0L, None))
  }
  guard physical_equal(entry.prepared.owner, execution) else {
    return Err(RequestIdentity)
  }
  guard state.attempts.get(slot) is Some(trace) &&
    physical_equal(trace, entry.trace) else {
    return Err(RequestIdentity)
  }
  guard call.raw_capture is Some(raw) else {
    return match call.usage_result {
      Some(Ok(_)) => Ok((true, 0L, None))
      Some(Err(issue)) => Ok((true, 0L, Some(issue)))
      None => Err(OutputIdentity)
    }
  }
  if call.polling || raw.usage_advancing {
    return Err(Session(@bounded.ConcurrentResume))
  }
  if raw.usage_retired {
    // A later answer/projection failure can leave the ordinary decode alias
    // retained even though envelope usage is already final. Retire that same
    // stopped child before proof persistence, without reopening its parser.
    if state.phase is DecodePhysicalResponse(_, _, cursor) &&
      !(cursor.phase is DecodeReclaimed) {
      let response = match call.terminal {
        Some(PhysicalChatResponse(response)) => response
        Some(PhysicalNativeResponse(native)) => {
          if !model_native_response_original(native, call) {
            return Err(RequestIdentity)
          }
          native.raw
        }
        _ => return Err(OutputIdentity)
      }
      guard cursor.raw_chat is Some(original) &&
        physical_equal(original, response) &&
        model_chat_response_original(response, call) &&
        physical_equal(raw, response.saved_raw.original) else {
        return Err(RequestIdentity)
      }
      cancel_model_response_decode(cursor)
    }
    return match raw.usage_result {
      Some(Ok(_)) => Ok((true, raw.usage_work.to_int64(), None))
      Some(Err(issue)) => Ok((true, raw.usage_work.to_int64(), Some(issue)))
      None => Err(OutputIdentity)
    }
  }
  if entry.trace.evidence is Some(_) {
    return Err(OutputIdentity)
  }
  let response = match call.terminal {
    Some(PhysicalChatResponse(response)) => response
    Some(PhysicalNativeResponse(native)) => {
      if !model_native_response_original(native, call) {
        return Err(RequestIdentity)
      }
      native.raw
    }
    // Missing saved custody stays missing. Failed/unknown persistence uses
    // its existing explicit reconciliation, not an automatic save retry.
    _ => return Err(OutputIdentity)
  }
  guard model_chat_response_original(response, call) &&
    physical_equal(raw, response.saved_raw.original) else {
    return Err(RequestIdentity)
  }
  match transfer_model_stopped_raw_usage_child(state, call, response, raw) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match advance_model_reconciled_raw_usage(call, response, quantum) {
    Ok((complete, work)) => Ok((complete, work, None))
    Err(issue) =>
      if raw.usage_retired {
        // Cancellation/exhaustion can retire a reader with partial usage.
        // Preserve that issue and let the original immutable failure proof
        // be saved; an outer binding/currentness refusal remains an error.
        Ok((true, raw.usage_work.to_int64(), Some(issue)))
      } else {
        Err(issue)
      }
  }
}

///|
fn transfer_model_stopped_raw_usage_child(
  state : ModelState,
  call : ModelPhysicalCall,
  response : ModelPhysicalChatResponse,
  raw : ModelRawCaptureSave,
) -> Result[Unit, ModelExecutionIssue] {
  guard state.phase is DecodePhysicalResponse(_, _, cursor) else {
    return Ok(())
  }
  if cursor.phase is DecodeReclaimed {
    return if raw.usage_reader is Some(_) {
      Ok(())
    } else {
      Err(OutputIdentity)
    }
  }
  guard cursor.raw_chat is Some(original) &&
    physical_equal(original, response) &&
    raw.usage_reader is None else {
    return Err(RequestIdentity)
  }
  let reader = match cursor.phase {
    ReadChat(child) => ChatUsage(child)
    ReadNative(child, native) => {
      guard physical_equal(native.raw, response) &&
        model_native_response_original(native, call) else {
        return Err(RequestIdentity)
      }
      NativeUsage(child)
    }
    _ => return Err(OutputIdentity)
  }
  // Transfer the exact remaining parser/facts, not a copy or a fresh budget.
  // Do not call cursor cancellation: that would erase the transferred facts.
  raw.usage_reader = Some(reader)
  cursor.phase = DecodeReclaimed
  cursor.raw_chat = None
  cursor.observation = None
  Ok(())
}
