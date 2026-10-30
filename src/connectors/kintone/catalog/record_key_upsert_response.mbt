///|
/// Response DATA for exactly the already selected original native branch.
/// No approval, physical claim, response custody or terminal ACK is issued.
pub struct RecordKeyUpsertAcknowledgement {
  priv mut self : RecordKeyUpsertAcknowledgement?
  priv request : RecordKeyUpsertRequest
  priv create : RecordCreateAcknowledgement?
  priv update : RecordUpdateAcknowledgement?
}

///|
pub fn project_record_key_upsert_acknowledgement(
  request : RecordKeyUpsertRequest,
  status : Int,
  bytes : Bytes,
  limits : RecordMutationLimits,
) -> Result[RecordKeyUpsertAcknowledgement, RecordMutationIssue] {
  if !mutation_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if !record_key_upsert_request_is_original(request) {
    return Err(UncorrelatedResult)
  }
  // Select one original codec, not whichever response shape happens to pass.
  // Failure never tries the other codec or chooses another physical request.
  let (create, update) = match request.operation {
    Insert => {
      guard request.create is Some(native) && request.update is None else {
        return Err(UncorrelatedResult)
      }
      match
        project_record_create_acknowledgement(native, status, bytes, limits) {
        Ok(value) => (Some(value), None)
        Err(issue) => return Err(issue)
      }
    }
    Update => {
      guard request.update is Some(native) && request.create is None else {
        return Err(UncorrelatedResult)
      }
      match
        project_record_update_acknowledgement(native, status, bytes, limits) {
        Ok(value) => (None, Some(value))
        Err(issue) => return Err(issue)
      }
    }
  }
  let result : RecordKeyUpsertAcknowledgement = {
    self: None,
    request,
    create,
    update,
  }
  result.self = Some(result)
  Ok(result)
}

///|
pub fn record_key_upsert_acknowledgement_is_original(
  value : RecordKeyUpsertAcknowledgement,
) -> Bool {
  value.self is Some(original) && physical_equal(original, value)
}

///|
pub fn record_key_upsert_acknowledgement_matches_request(
  value : RecordKeyUpsertAcknowledgement,
  request : RecordKeyUpsertRequest,
) -> Bool {
  if !record_key_upsert_acknowledgement_is_original(value) ||
    !record_key_upsert_request_is_original(request) ||
    !physical_equal(value.request, request) {
    return false
  }
  match (request.operation, value.create, value.update) {
    (Insert, Some(response), None) =>
      record_create_acknowledgement_is_original(response) &&
      request.create is Some(native) &&
      physical_equal(record_create_acknowledgement_request(response), native)
    (Update, None, Some(response)) =>
      record_update_acknowledgement_is_original(response) &&
      request.update is Some(native) &&
      physical_equal(record_update_acknowledgement_request(response), native)
    _ => false
  }
}

///|
pub fn record_key_upsert_create_acknowledgement(
  value : RecordKeyUpsertAcknowledgement,
) -> RecordCreateAcknowledgement? {
  if record_key_upsert_acknowledgement_is_original(value) {
    value.create
  } else {
    None
  }
}

///|
pub fn record_key_upsert_update_acknowledgement(
  value : RecordKeyUpsertAcknowledgement,
) -> RecordUpdateAcknowledgement? {
  if record_key_upsert_acknowledgement_is_original(value) {
    value.update
  } else {
    None
  }
}

///|
/// Existing typed branch outcome retained beside the same original request
/// and response. The actual Host still binds its full admitted UPSERT Preview,
/// intended values, saved response and current durable claim before use.
pub struct RecordKeyUpsertEffectOutcome {
  priv request : RecordKeyUpsertRequest
  priv response : RecordKeyUpsertAcknowledgement
  priv create : RecordCreateEffectOutcome?
  priv update : RecordUpdateEffectOutcome?
}

///|
pub fn project_record_key_upsert_effect_outcome(
  request : RecordKeyUpsertRequest,
  response : RecordKeyUpsertAcknowledgement,
  limits : RecordMutationLimits,
) -> Result[RecordKeyUpsertEffectOutcome, RecordMutationIssue] {
  if !mutation_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if !record_key_upsert_acknowledgement_matches_request(response, request) {
    return Err(UncorrelatedResult)
  }
  let (create, update) = match request.operation {
    Insert => {
      guard request.create is Some(native) && response.create is Some(ack) else {
        return Err(UncorrelatedResult)
      }
      match project_record_create_effect_outcome(native, ack, limits) {
        Ok(value) => (Some(value), None)
        Err(issue) => return Err(issue)
      }
    }
    Update => {
      guard request.update is Some(native) && response.update is Some(ack) else {
        return Err(UncorrelatedResult)
      }
      match project_record_update_effect_outcome(native, ack, limits) {
        Ok(value) => (None, Some(value))
        Err(issue) => return Err(issue)
      }
    }
  }
  Ok({ request, response, create, update, })
}

///|
pub fn record_key_upsert_effect_outcome_wire(
  value : RecordKeyUpsertEffectOutcome,
) -> String {
  match (value.create, value.update) {
    (Some(original), None) => record_create_effect_outcome_wire(original)
    (None, Some(original)) => record_update_effect_outcome_wire(original)
    _ => abort("original keyed UPSERT outcome branch invariant")
  }
}

///|
pub fn record_key_upsert_effect_outcome_response_sha256(
  value : RecordKeyUpsertEffectOutcome,
) -> String {
  match (value.create, value.update) {
    (Some(original), None) =>
      record_create_effect_outcome_response_sha256(original)
    (None, Some(original)) =>
      record_update_effect_outcome_response_sha256(original)
    _ => abort("original keyed UPSERT outcome branch invariant")
  }
}

///|
pub fn record_key_upsert_effect_outcome_matches_request(
  value : RecordKeyUpsertEffectOutcome,
  request : RecordKeyUpsertRequest,
) -> Bool {
  if !record_key_upsert_acknowledgement_matches_request(value.response, request) ||
    !physical_equal(value.request, request) {
    return false
  }
  match (request.operation, value.create, value.update) {
    (Insert, Some(projected), None) =>
      request.create is Some(native) &&
      record_create_effect_outcome_matches_request(projected, native)
    (Update, None, Some(projected)) =>
      request.update is Some(native) &&
      record_update_effect_outcome_matches_request(projected, native)
    _ => false
  }
}
