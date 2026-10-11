///|
// Consume the original entered transport's raw envelope under the existing
// Model response phase. The profile and raw Artifact do not authorize send.
fn begin_chat_model_response(
  state : ModelState,
  prepared : PreparedModelRequest,
  raw : ModelPhysicalChatResponse,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 1, 1)
  }
  guard state.pending_response is Some(original_call) &&
    model_chat_response_original(raw, original_call) &&
    state.physical_plans.get(prepared.request.slot) is Some(plan) &&
    plan.response_profile is Some(profile) &&
    @environment.model_response_profile_completion_basis(profile) ==
    "generation_finish" &&
    valid_cid(raw.raw_response_artifact_cid) &&
    !raw.observed_at.is_empty() &&
    raw.status >= 100 &&
    raw.status <= 599 else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  if !raw.transport_eof {
    state.observing_response = false
    state.outcomes.push(UnresolvedUnknown)
    return @bounded.Failed(UnknownCalls, 1, 1)
  }
  let limits = @environment.model_response_profile_limits(profile)
  let chat = match start_chat_envelope_decode(raw.body, limits) {
    Ok(chat) => chat
    Err(issue) => return @bounded.Failed(issue, 1, 1)
  }
  let observation : @publication.ModelCaptureObservation = {
    origin: @publication.Reported,
    provider_model: None,
    provider_revision: None,
    provider_request_id: None,
    gateway_request_id: None,
    input_tokens: None,
    output_tokens: None,
    provider_finish_reason: None,
    historical_finish_reason: None,
    response_profile_cid: Some(
      @environment.model_response_profile_identity(profile),
    ),
    response_complete: None,
    raw_response_artifact_cid: Some(raw.raw_response_artifact_cid),
    provider_metadata: raw.provider_metadata,
    observed_at: raw.observed_at,
  }
  state.phase = DecodePhysicalResponse(
    prepared,
    {
      body: raw.body,
      observation,
      transport_eof: raw.transport_eof,
      endpoint_complete: false,
      answer_complete: false,
    },
    {
      phase: ReadChat(chat),
      limits,
      remaining: limits.parse_work,
      raw_chat: Some(raw),
      observation: None,
    },
  )
  @bounded.Continue(1, 1)
}

///|
fn advance_chat_model_response(
  state : ModelState,
  cursor : ModelResponseDecode,
  chat : ChatEnvelopeDecode,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  guard cursor.raw_chat is Some(raw) &&
    state.pending_response is Some(call) &&
    call.terminal is Some(PhysicalChatResponse(original)) &&
    physical_equal(original, raw) else {
    return @bounded.Failed(RequestIdentity, 1, 1)
  }
  // Keep quantities already read from the admitted original even when a
  // later stop or child work failure prevents shape or answer completion.
  if chat.facts is Some(facts) {
    match retain_chat_model_usage(state, call, facts, false) {
      Err(issue) => return @bounded.Failed(issue, 1, 1)
      Ok(_) => ()
    }
  }
  match advance_chat_envelope_decode(chat) {
    Err(issue) => @bounded.Failed(issue, 1, 1)
    Ok(None) => {
      if chat.facts is Some(facts) {
        match retain_chat_model_usage(state, call, facts, false) {
          Err(issue) => return @bounded.Failed(issue, 1, 1)
          Ok(_) => ()
        }
      }
      cursor.remaining = chat.remaining
      @bounded.Continue(1, 1)
    }
    Ok(Some(facts)) => {
      // Preserve usage even on refusal, bad shape, HTTP failure or later
      // cancellation. Unknown remains None and is never an observed zero.
      match retain_chat_model_usage(state, call, facts, true) {
        Err(issue) => return @bounded.Failed(issue, 1, 1)
        Ok(_) => ()
      }
      if raw.status < 200 || raw.status >= 300 {
        state.observing_response = false
        return accept_failed_model_slot(state, ProviderError)
      }
      if !chat_envelope_complete(facts) {
        state.observing_response = false
        return accept_failed_model_slot(
          state,
          if facts.refused {
            Refusal
          } else if facts.finish_reason == Some("length") {
            Truncated
          } else {
            SchemaInvalid
          },
        )
      }
      guard state.physical_plans.get(state.next_slot) is Some(plan) &&
        plan.response_profile is Some(profile) else {
        return @bounded.Failed(RequestIdentity, 1, 1)
      }
      cursor.observation = Some({
        origin: @publication.Reported,
        provider_model: facts.provider_model,
        provider_revision: None,
        provider_request_id: facts.provider_request_id,
        gateway_request_id: None,
        input_tokens: facts.input_tokens,
        output_tokens: facts.output_tokens,
        provider_finish_reason: facts.finish_reason,
        historical_finish_reason: None,
        response_profile_cid: Some(
          @environment.model_response_profile_identity(profile),
        ),
        response_complete: None,
        raw_response_artifact_cid: Some(raw.raw_response_artifact_cid),
        provider_metadata: raw.provider_metadata,
        observed_at: raw.observed_at,
      })
      let parse = match
        @source.start_json_parse(
          facts.answer.unwrap(),
          {
            max_input_bytes: cursor.limits.response_bytes,
            max_nodes: cursor.limits.parse_nodes,
            max_depth: cursor.limits.parse_depth,
          },
          data_keys=true,
        ) {
        Ok(parse) => parse
        Err(_) => return @bounded.Failed(OutputValue, 1, 1)
      }
      // One cumulative envelope+answer budget. Completing the envelope does
      // not reset the original work or create another physical operation.
      cursor.remaining = chat.remaining
      cursor.phase = ParseAnswer(parse)
      @bounded.Continue(1, 1)
    }
  }
}

///|
fn retain_chat_model_usage(
  state : ModelState,
  call : ModelPhysicalCall,
  facts : ChatEnvelopeFacts,
  terminal : Bool,
) -> Result[Unit, ModelExecutionIssue] {
  if call.usage_result is Some(result) {
    return result
  }
  let usage : ModelPhysicalUsage = {
    input_tokens: facts.input_tokens,
    output_tokens: facts.output_tokens,
  }
  if terminal ||
    (usage.input_tokens is Some(_) && usage.output_tokens is Some(_)) {
    observe_model_physical_usage(state, call, PhysicalUnknown(usage))
  } else {
    // Partial actuals stay on the original trace, without resolving the
    // uncertain token reservation or caching unknown as a final observation.
    observe_original_model_physical_usage(state, call, PhysicalUnknown(usage))
  }
}
