///|
// Four original borrows, not a self-reported tuple or another response Owner.
pub struct ModelPhysicalNativeResponse {
  priv raw : ModelPhysicalChatResponse
  priv original : NativeDecisionRequest
  priv provider : AdmittedModelProvider
  priv probability : @environment.DecisionProbabilityProfile
}

///|
fn model_native_response_original(
  response : ModelPhysicalNativeResponse,
  call : ModelPhysicalCall,
) -> Bool {
  guard model_chat_response_original(response.raw, call) &&
    call.entry is Some(entry) else {
    return false
  }
  let state = entry.prepared.owner.state
  guard state.requests.get(entry.slot) is Some(prepared) &&
    state.source is Provider(provider) &&
    physical_equal(provider, response.provider.provider) &&
    native_decision_request_matches(
      response.original,
      response.provider,
      prepared.request,
    ) &&
    state.physical_plans.get(entry.slot) is Some(plan) &&
    physical_equal(plan.request, prepared.request) &&
    plan.invocation is Asynchronous(_) &&
    plan.response_profile is Some(profile) else {
    return false
  }
  @environment.model_response_profile_completion_basis(profile) ==
  "native_decision" &&
  @environment.check_model_response_profile_probability(
    profile,
    prepared.request.task,
    response.probability,
  )
  is Ok(_)
}

///|
// The saved raw receipt supplies the original call, Slot, attempt and Store
// custody. Profile cross-references do not issue installation or send grants.
pub fn model_physical_saved_native_response(
  raw : ModelPhysicalChatResponse,
  original : NativeDecisionRequest,
  provider : AdmittedModelProvider,
  probability : @environment.DecisionProbabilityProfile,
) -> Result[ModelPhysicalCallPoll, ModelExecutionIssue] {
  let response = { raw, original, provider, probability, }
  if !model_native_response_original(response, raw.saved_raw.original.call) {
    return Err(RequestIdentity)
  }
  Ok(PhysicalNativeResponse(response))
}

///|
fn begin_native_model_response(
  state : ModelState,
  prepared : PreparedModelRequest,
  native : ModelPhysicalNativeResponse,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 1, 1)
  }
  guard state.pending_response is Some(call) &&
    model_native_response_original(native, call) &&
    state.physical_plans.get(prepared.request.slot) is Some(plan) &&
    plan.response_profile is Some(profile) else {
    return @bounded.Failed(RequestIdentity, 1, 1)
  }
  let raw = native.raw
  if !raw.transport_eof {
    state.observing_response = false
    state.outcomes.push(UnresolvedUnknown)
    return @bounded.Failed(UnknownCalls, 1, 1)
  }
  let limits = @environment.model_response_profile_limits(profile)
  let child = match start_native_envelope_decode(raw.body, limits) {
    Ok(child) => child
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
      phase: ReadNative(child, native),
      limits,
      remaining: limits.parse_work,
      raw_chat: Some(raw),
      observation: None,
    },
  )
  @bounded.Continue(1, 1)
}

///|
fn advance_native_model_response(
  state : ModelState,
  cursor : ModelResponseDecode,
  child : NativeEnvelopeDecode,
  native : ModelPhysicalNativeResponse,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  guard state.pending_response is Some(call) &&
    call.terminal is Some(PhysicalNativeResponse(original)) &&
    physical_equal(original, native) &&
    model_native_response_original(native, call) else {
    return @bounded.Failed(RequestIdentity, 1, 1)
  }
  if child.facts is Some(facts) {
    match retain_chat_model_usage(state, call, facts, false) {
      Err(issue) => return @bounded.Failed(issue, 1, 1)
      Ok(_) => ()
    }
  }
  match advance_native_envelope_decode(child) {
    Err(issue) => @bounded.Failed(issue, 1, 1)
    Ok(None) => {
      if child.facts is Some(facts) {
        match retain_chat_model_usage(state, call, facts, false) {
          Err(issue) => return @bounded.Failed(issue, 1, 1)
          Ok(_) => ()
        }
      }
      cursor.remaining = child.remaining
      @bounded.Continue(1, 1)
    }
    Ok(Some(root)) => {
      let facts = child.facts.unwrap()
      match retain_chat_model_usage(state, call, facts, true) {
        Err(issue) => return @bounded.Failed(issue, 1, 1)
        Ok(_) => ()
      }
      retire_model_raw_usage_child(call) |> ignore
      if native.raw.status < 200 || native.raw.status >= 300 || facts.malformed {
        cancel_native_envelope_decode(child)
        state.observing_response = false
        return accept_failed_model_slot(
          state,
          if facts.malformed {
            SchemaInvalid
          } else {
            ProviderError
          },
        )
      }
      // Reuse the existing finite synchronous alias codec. Its work units
      // remain codec units, not Ledger planning or parent KernelStep units.
      let (wire, work) = match
        project_native_decision_answers(
          native.original,
          native.provider,
          native.original.request.unwrap(),
          root,
          cursor.limits.response_bytes,
          cursor.limits.parse_nodes,
          cursor.limits.parse_depth,
          child.remaining,
        ) {
        Ok(value) => value
        Err(Limit) => return @bounded.Failed(WorkLimit, 1, 1)
        Err(_) => return @bounded.Failed(OutputValue, 1, 1)
      }
      cursor.remaining = child.remaining - work
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
        provider_finish_reason: None,
        historical_finish_reason: None,
        response_profile_cid: Some(
          @environment.model_response_profile_identity(profile),
        ),
        response_complete: None,
        raw_response_artifact_cid: Some(native.raw.raw_response_artifact_cid),
        provider_metadata: native.raw.provider_metadata,
        observed_at: native.raw.observed_at,
      })
      let parse = match
        @source.start_json_parse(
          wire,
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
      cancel_native_envelope_decode(child)
      cursor.phase = ParseNativeAnswer(
        parse,
        native.original,
        native.probability,
      )
      @bounded.Continue(1, 1)
    }
  }
}
