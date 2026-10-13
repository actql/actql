///|
// Physical codec completeness is distinct from optional reported metadata.
// The installed decoder supplies actual facts; the profile alone supplies none.
fn begin_reported_model_response(
  state : ModelState,
  prepared : PreparedModelRequest,
  physical : ModelPhysicalResponse,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 1, 1)
  }
  guard state.physical_plans.get(prepared.request.slot) is Some(plan) &&
    plan.response_profile is Some(profile) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  let observation = physical.observation
  if !valid_reported_model_observation(
      profile,
      observation,
      physical.transport_eof,
      physical.endpoint_complete,
      physical.answer_complete,
    ) {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  let response : ModelObservedResponse = { value: physical.value, observation, }
  if observation.provider_metadata is Some(metadata) {
    if @canonical.object_field_count(metadata) is None {
      return @bounded.Failed(OutputIdentity, 1, 1)
    }
    let bounds = @environment.model_response_profile_limits(profile)
    let writer = @encode.hashing_writer(
      bounds.metadata_bytes,
      bounds.metadata_nodes,
      bounds.metadata_depth,
    ) catch {
      _ => return @bounded.Failed(OutputIdentity, 1, 1)
    }
    state.phase = CheckPhysicalMetadata(
      prepared,
      response,
      @canonical.start_emit(metadata, writer),
      writer,
    )
    return @bounded.Continue(1, 1)
  }
  begin_reported_model_value(state, prepared, response)
}

///|
fn valid_reported_model_observation(
  profile : @environment.ModelResponseProfile,
  observation : @publication.ModelCaptureObservation,
  transport_eof : Bool,
  endpoint_complete : Bool,
  answer_complete : Bool,
) -> Bool {
  if !transport_eof ||
    !endpoint_complete ||
    !answer_complete ||
    observation.origin != @publication.Reported ||
    observation.response_complete != Some(true) ||
    observation.response_profile_cid !=
    Some(@environment.model_response_profile_identity(profile)) ||
    observation.historical_finish_reason is Some(_) ||
    observation.observed_at.is_empty() ||
    !valid_model_optional_text(observation.provider_model) ||
    !valid_model_optional_text(observation.provider_revision) ||
    !valid_model_optional_text(observation.provider_request_id) ||
    !valid_model_optional_text(observation.gateway_request_id) ||
    !valid_model_optional_text(observation.provider_finish_reason) ||
    !valid_model_optional_tokens(observation.input_tokens) ||
    !valid_model_optional_tokens(observation.output_tokens) {
    return false
  }
  if observation.raw_response_artifact_cid is Some(cid) && !valid_cid(cid) {
    return false
  }
  true
}

///|
fn advance_reported_model_metadata(
  state : ModelState,
  prepared : PreparedModelRequest,
  response : ModelObservedResponse,
  cursor : @canonical.CanonicalEmit,
  writer : @encode.Writer,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  try {
    if !@canonical.advance_emit(cursor) {
      return @bounded.Continue(1, 1)
    }
    @encode.finish_hash_usage(writer) |> ignore
    @canonical.cancel_emit(cursor)
    @encode.cancel_writer(writer)
    begin_reported_model_value(state, prepared, response)
  } catch {
    _ => {
      @canonical.cancel_emit(cursor)
      @encode.cancel_writer(writer)
      @bounded.Failed(OutputIdentity, 1, 1)
    }
  }
}

///|
fn begin_reported_model_value(
  state : ModelState,
  prepared : PreparedModelRequest,
  response : ModelObservedResponse,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  let cursor = match
    @admitted.start_recheck_runtime_value(
      response.value,
      @environment.model_task_output(state.task),
      state.limits.value_limits,
    ) {
    Some(cursor) => cursor
    None => return @bounded.Failed(OutputValue, 1, 1)
  }
  state.phase = CheckResponse(
    prepared.request,
    response,
    prepared.key_cid,
    cursor,
  )
  @bounded.Continue(1, 1)
}

///|
// Only the response already admitted by this entered execution can supply new
// evidence. A declared profile CID or a replay body cannot forge this origin.
fn model_reported_response_owned(
  state : ModelState,
  request : ModelRequest,
  response : ModelObservedResponse,
) -> Bool {
  guard state.pending_response is Some(call) &&
    call.entry is Some(entry) &&
    entry.slot == request.slot &&
    state.requests.get(entry.slot) is Some(prepared) &&
    physical_equal(prepared.request, request) else {
    return false
  }
  let original = match call.terminal {
    Some(PhysicalResponse(original)) => original
    Some(PhysicalEncodedResponse(encoded)) => {
      guard call.decoded_response is Some(original) &&
        physical_equal(encoded.observation, original.observation) else {
        return false
      }
      original
    }
    Some(PhysicalChatResponse(raw)) => {
      guard call.decoded_response is Some(original) &&
        model_chat_response_original(raw, call) &&
        original.observation.raw_response_artifact_cid ==
        Some(raw.raw_response_artifact_cid) &&
        original.observation.observed_at == raw.observed_at &&
        raw.transport_eof &&
        raw.status >= 200 &&
        raw.status < 300 else {
        return false
      }
      original
    }
    Some(PhysicalNativeResponse(native)) => {
      let raw = native.raw
      guard call.decoded_response is Some(original) &&
        model_native_response_original(native, call) &&
        original.observation.raw_response_artifact_cid ==
        Some(raw.raw_response_artifact_cid) &&
        original.observation.observed_at == raw.observed_at &&
        raw.transport_eof &&
        raw.status >= 200 &&
        raw.status < 300 else {
        return false
      }
      original
    }
    _ => return false
  }
  physical_equal(original.value, response.value) &&
  physical_equal(original.observation, response.observation) &&
  original.transport_eof &&
  original.endpoint_complete &&
  original.answer_complete &&
  state.physical_plans.get(entry.slot) is Some(plan) &&
  plan.response_profile is Some(profile) &&
  response.observation.response_profile_cid ==
  Some(@environment.model_response_profile_identity(profile)) &&
  response.observation.response_complete == Some(true)
}
