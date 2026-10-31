///|
/// Response DATA for the same original UPDATE, not a dispatch receipt or a
/// terminal Ledger transition. Saved-response/current duties stay with Host.
pub struct RecordUpdateEffectOutcome {
  priv request : RecordUpdateRequest
  priv response : RecordUpdateAcknowledgement
  priv document : @encode.EncodedDocument
}

///|
pub fn project_record_update_effect_outcome(
  request : RecordUpdateRequest,
  response : RecordUpdateAcknowledgement,
  limits : RecordMutationLimits,
) -> Result[RecordUpdateEffectOutcome, RecordMutationIssue] {
  project_record_update_effect_outcome_for_operation(
    request, response, limits, false,
  )
}

///|
// The original keyed UPSERT issuer selects this branch before response
// decoding. Standalone UPDATE retains its exact original wire.
fn project_record_update_effect_outcome_for_operation(
  request : RecordUpdateRequest,
  response : RecordUpdateAcknowledgement,
  limits : RecordMutationLimits,
  upsert : Bool,
) -> Result[RecordUpdateEffectOutcome, RecordMutationIssue] {
  if !mutation_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if !record_update_request_is_original(request) ||
    !record_update_acknowledgement_is_original(response) ||
    !physical_equal(response.request, request) ||
    request.records.length() != 1 ||
    response.records.length() != 1 {
    return Err(UncorrelatedResult)
  }
  let (id, revision) = response.records[0]
  if id.length() > limits.max_identity_bytes ||
    revision.length() > limits.max_identity_bytes - id.length() {
    return Err(BudgetExceeded)
  }
  let writer = @encode.writer(
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let document = try {
    @encode.begin_ordered_object(writer)
    if upsert {
      @encode.ordered_key(writer, "action")
      @encode.string_value(writer, "updated")
    }
    @encode.ordered_key(writer, "result")
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "record_id")
    @encode.string_value(writer, id)
    @encode.ordered_key(writer, "revision")
    @encode.string_value(writer, revision)
    @encode.end_object(writer)
    @encode.ordered_key(writer, "state")
    @encode.string_value(writer, "applied")
    @encode.end_object(writer)
    @encode.finish_document(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(BudgetExceeded)
    }
  }
  Ok({ request, response, document, })
}

///|
pub fn record_update_effect_outcome_wire(
  value : RecordUpdateEffectOutcome,
) -> String {
  @encode.document_text(value.document)
}

///|
pub fn record_update_effect_outcome_response_sha256(
  value : RecordUpdateEffectOutcome,
) -> String {
  value.response.response_sha256
}

///|
pub fn record_update_effect_outcome_matches_request(
  value : RecordUpdateEffectOutcome,
  request : RecordUpdateRequest,
) -> Bool {
  record_update_request_is_original(request) &&
  record_update_acknowledgement_is_original(value.response) &&
  physical_equal(value.request, request) &&
  physical_equal(value.response.request, request)
}
