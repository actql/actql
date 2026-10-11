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
  for (old, actual) in [
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
  let result = if raw.usage_reader is Some(reader) && reader.facts is Some(facts) {
    retain_reconciled_raw_usage(call, facts)
  } else {
    Ok(())
  }
  if raw.usage_reader is Some(reader) {
    cancel_chat_envelope_decode(reader)
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
    call.entry is Some(entry) &&
    call.terminal is Some(PhysicalUnknown(_) | PhysicalRejected(_, _)) else {
    return Err(RequestIdentity)
  }
  if raw.usage_retired {
    return raw.usage_result.unwrap_or(Ok(())).map(_ => {
      (true, raw.usage_work.to_int64())
    })
  }
  if raw.usage_advancing {
    return Err(Session(@bounded.ConcurrentResume))
  }
  raw.usage_advancing = true
  let result = advance_reconciled_raw_usage_owned(call, response, raw, entry, quantum)
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
    if raw.usage_reader is Some(reader) && reader.facts is Some(facts) {
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
          call, raw, Err(Authorization(@publication_host.Authorization(issue))),
        )
      Err(_) => return finish_reconciled_raw_usage(call, raw, Err(RequestIdentity))
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
      match start_chat_envelope_decode(
        response.body, @environment.model_response_profile_limits(profile),
      ) {
        Err(issue) => return finish_reconciled_raw_usage(call, raw, Err(issue))
        Ok(reader) => raw.usage_reader = Some(reader)
      }
    } else {
      match advance_chat_envelope_decode(raw.usage_reader.unwrap()) {
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
  result.map(_ => { (true, raw.usage_work.to_int64()) })
}
