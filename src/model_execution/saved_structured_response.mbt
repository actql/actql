///|
/// Selected structured output from an installed decoder, with the original
/// Store receipt as a separate nominal borrow. The decoded text is never Raw.
pub struct ModelPhysicalSavedStructuredResponse {
  priv receipt : ModelSavedRawReceipt
  priv encoded : ModelPhysicalEncodedResponse
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
/// Only the original saved 2xx/EOF response may supply structured output.
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
  if status < 200 || status >= 300 || !transport_eof {
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
  guard read_decoded(call, receipt, bytes) is Some(decoded) &&
    model_structured_receipt_owned(call, receipt) &&
    !state.stop_requested &&
    !call.cancel_requested else {
    return Err(OutputIdentity)
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
  if !valid_reported_model_observation(
      profile,
      observation,
      transport_eof,
      decoded.endpoint_complete,
      decoded.answer_complete,
    ) {
    return Err(OutputIdentity)
  }
  let encoded = { ..decoded, observation, transport_eof, }
  Ok(PhysicalSavedStructuredResponse({ receipt, encoded, }))
}
