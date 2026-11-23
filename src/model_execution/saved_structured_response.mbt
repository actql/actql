///|
/// Observations from the same complete saved response apply even when the
/// selected codec rejects the answer.
pub(all) struct ModelSavedStructuredDecoded {
  answer : Result[String, ModelProviderFailure]
  observation : @publication.ModelCaptureObservation
}

///|
/// Selected structured output from an installed decoder, with the original
/// Store receipt as a separate nominal borrow. The decoded text is never Raw.
pub struct ModelPhysicalSavedStructuredResponse {
  priv receipt : ModelSavedRawReceipt
  priv result : Result[ModelPhysicalEncodedResponse, ModelProviderFailure]
  priv observation : @publication.ModelCaptureObservation?
}

///|
fn model_call_requires_structured_receipt(call : ModelPhysicalCall) -> Bool {
  call.original_binding is Some(binding) &&
  binding.plan.invocation is AsynchronousSavedStructured(_, _, _)
}

///|
fn model_structured_receipt_owned(
  call : ModelPhysicalCall,
  receipt : ModelSavedRawReceipt,
) -> Bool {
  model_call_requires_structured_receipt(call) &&
  model_raw_capture_call_owned(call) &&
  call.raw_capture is Some(original) &&
  physical_equal(original, receipt.original) &&
  original.saved is Some(saved) &&
  physical_equal(saved, receipt)
}

///|
fn model_saved_structured_response_original(
  value : ModelPhysicalSavedStructuredResponse,
  call : ModelPhysicalCall,
) -> Bool {
  model_structured_receipt_owned(call, value.receipt)
}

///|
/// Classify a closed HTTP response from the same verified Store receipt.
/// Only a complete 2xx response may supply a structured answer.
/// Verify the borrowed Store bytes against the saved descriptor before
/// invoking the decoder retained by this physical Plan. An asynchronous
/// SDK port uses this callback to read the same invocation's result; a
/// synchronous codec reads these bytes directly. Both remain funded by the
/// installed caller. Common checks the selected answer's original Task type.
pub fn model_physical_saved_structured_response(
  call : ModelPhysicalCall,
  receipt : ModelSavedRawReceipt,
  bytes : Bytes,
) -> Result[ModelPhysicalCallPoll, ModelExecutionIssue] {
  guard model_structured_receipt_owned(call, receipt) &&
    call.original_binding is Some(binding) &&
    binding.plan.invocation is AsynchronousSavedStructured(_, _, read_decoded) &&
    binding.plan.response_profile is Some(profile) &&
    call.entry is Some(entry) else {
    return Err(RequestIdentity)
  }
  let raw = receipt.original.response
  let (status, transport_eof, observed_at) = @publication.model_raw_response_transport_facts(
    raw,
  )
  if !transport_eof {
    return Err(OutputIdentity)
  }
  let (_, _, _, content_cid, byte_count) = @publication.model_raw_response_store_binding(
    raw,
  )
  if bytes.length() != byte_count || "sha256:" + @sha.hex(bytes) != content_cid {
    return Err(RequestIdentity)
  }
  let state = entry.prepared.owner.state
  if state.stop_requested || call.cancel_requested {
    return Err(Cancelled)
  }
  if status < 200 || status >= 300 {
    let failure = match status {
      429 => RateLimit
      _ => ProviderError
    }
    return Ok(
      PhysicalSavedStructuredResponse({
        receipt,
        result: Err(failure),
        observation: None,
      }),
    )
  }
  let selected = read_decoded(call, receipt, bytes)
  guard model_structured_receipt_owned(call, receipt) &&
    !state.stop_requested &&
    !call.cancel_requested else {
    return Err(OutputIdentity)
  }
  guard selected is Some(decoded) else {
    return Ok(
      PhysicalSavedStructuredResponse({
        receipt,
        result: Err(SchemaInvalid),
        observation: None,
      }),
    )
  }
  let observation = {
    ..decoded.observation,
    raw_response_artifact_cid: Some(
      @publication.run_evidence_value_identity(
        @publication.model_raw_response_value(raw),
      ),
    ),
    observed_at,
  }
  if !valid_reported_model_observation_fields(profile, observation) ||
    observation.observed_at.length() > 64 ||
    observation.provider_model.unwrap_or("").length() > 256 ||
    observation.provider_request_id.unwrap_or("").length() > 256 ||
    observation.provider_finish_reason.unwrap_or("").length() > 256 ||
    !valid_saved_sdk_report_metadata(profile, observation.provider_metadata) ||
    (decoded.answer is Ok(_) && observation.response_complete != Some(true)) {
    return Err(OutputIdentity)
  }
  let result = decoded.answer.map(body => {
    body,
    observation,
    transport_eof,
    endpoint_complete: true,
    answer_complete: true,
  })
  Ok(
    PhysicalSavedStructuredResponse({
      receipt,
      result,
      observation: Some(observation),
    }),
  )
}

///|
fn saved_sdk_report_metadata_selected(
  profile : @environment.ModelResponseProfile,
) -> Bool {
  for
    index in 0..<@environment.model_response_profile_observation_count(profile) {
    if @environment.model_response_profile_observation_at(profile, index) ==
      Some("provider_metadata") {
      return true
    }
  }
  false
}

///|
fn valid_saved_sdk_metadata_scalar(name : String, value : String) -> Bool {
  !name.is_empty() &&
  name.length() <= 64 &&
  name.iter().all(c => c is ('a'..='z' | '0'..='9' | '_')) &&
  !value.is_empty() &&
  value.length() <= 256
}

///|
/// Registered SDK observations currently carry one named scalar selected by
/// their verified codec. The original Profile limits its wire and shape.
pub fn admit_saved_sdk_report_metadata(
  profile : @environment.ModelResponseProfile,
  name : String,
  value : String,
) -> @canonical.CanonicalValue? {
  if !saved_sdk_report_metadata_selected(profile) ||
    !valid_saved_sdk_metadata_scalar(name, value) {
    return None
  }
  let limits = @environment.model_response_profile_limits(profile)
  try {
    let fields : Map[String, Json] = Map([])
    fields[name] = Json::string(value)
    let metadata = @canonical.from_json(
      Json::object(fields),
      Int::min(2, limits.metadata_nodes),
      limits.metadata_depth,
      name.length() + value.length(),
    )
    @canonical.measure_value(
      metadata,
      limits.metadata_bytes,
      limits.metadata_nodes,
      limits.metadata_depth,
    )
    |> ignore
    Some(metadata)
  } catch {
    _ => None
  }
}

///|
fn valid_saved_sdk_report_metadata(
  profile : @environment.ModelResponseProfile,
  metadata : @canonical.CanonicalValue?,
) -> Bool {
  guard metadata is Some(metadata) else { return true }
  guard saved_sdk_report_metadata_selected(profile) &&
    @canonical.object_field_count(metadata) == Some(1) &&
    @canonical.object_fields(metadata) is Some(fields) &&
    fields[0] is (name, @canonical.String(value)) &&
    valid_saved_sdk_metadata_scalar(name, value) else {
    return false
  }
  let limits = @environment.model_response_profile_limits(profile)
  try {
    @canonical.measure_value(
      metadata,
      limits.metadata_bytes,
      limits.metadata_nodes,
      limits.metadata_depth,
    )
    |> ignore
    true
  } catch {
    _ => false
  }
}
