///|
/// Typed provider DATA for exactly one original CREATE request. The saved
/// response, Preview, dispatch claim and terminal Ledger remain their owners'.
pub struct RecordCreateEffectOutcome {
  priv request : RecordCreateRequest
  priv response : RecordCreateAcknowledgement
  priv document : @encode.EncodedDocument
}

///|
pub fn project_record_create_effect_outcome(
  request : RecordCreateRequest,
  response : RecordCreateAcknowledgement,
  limits : RecordMutationLimits,
) -> Result[RecordCreateEffectOutcome, RecordMutationIssue] {
  project_record_create_effect_outcome_for_operation(
    request, response, limits, false,
  )
}

///|
// The original keyed UPSERT issuer selects this branch before response
// decoding. Standalone CREATE retains its exact original wire.
fn project_record_create_effect_outcome_for_operation(
  request : RecordCreateRequest,
  response : RecordCreateAcknowledgement,
  limits : RecordMutationLimits,
  upsert : Bool,
) -> Result[RecordCreateEffectOutcome, RecordMutationIssue] {
  if !mutation_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if !record_create_request_is_original(request) ||
    !record_create_acknowledgement_is_original(response) ||
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
      @encode.string_value(writer, "created")
    }
    @encode.ordered_key(writer, "result")
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "created")
    @encode.bool_value(writer, true)
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
pub fn record_create_effect_outcome_wire(
  value : RecordCreateEffectOutcome,
) -> String {
  @encode.document_text(value.document)
}

///|
pub fn record_create_effect_outcome_response_sha256(
  value : RecordCreateEffectOutcome,
) -> String {
  value.response.response_sha256
}

///|
pub fn record_create_effect_outcome_matches_request(
  value : RecordCreateEffectOutcome,
  request : RecordCreateRequest,
) -> Bool {
  physical_equal(value.request, request) &&
  physical_equal(value.response.request, request)
}
