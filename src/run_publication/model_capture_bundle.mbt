///|
/// Structural admission of persisted observation bytes, not execution,
/// egress or publication authority. The restoring model owner must check
/// each record against its freshly prepared request and typed output.
struct ModelCaptureStorage {
  mut bundle : RunEvidenceValue?
  mut records : @json.FrozenArray[@json.CanonicalValue]?
  mut uses : Int
}

///|
pub struct ModelCaptureBundleRead {
  storage : ModelCaptureStorage
  mut released : Bool
}

///|
pub struct ModelCaptureRecordRead {
  evidence : RunEvidenceValue
  response : @json.CanonicalValue
}

///|
/// Historical admitted fields retain their historical provenance. New
/// reported fields are observations, not independent proof of provider truth.
pub(all) enum ModelCaptureObservationOrigin {
  HistoricalAdmitted
  Reported
} derive(Eq, Debug)

///|
/// A structural read of the original immutable evidence, not a send,
/// completeness or publication capability. The restoring execution still
/// binds its selected profile, attempt, typed output and authenticated custody.
pub(all) struct ModelCaptureObservation {
  origin : ModelCaptureObservationOrigin
  provider_model : String?
  provider_revision : String?
  provider_request_id : String?
  gateway_request_id : String?
  input_tokens : Int64?
  output_tokens : Int64?
  provider_finish_reason : String?
  historical_finish_reason : String?
  response_profile_cid : String?
  response_complete : Bool?
  raw_response_artifact_cid : String?
  provider_metadata : @json.CanonicalValue?
  observed_at : String
}

///|
/// The Host supplies exact bytes read from authenticated, confirmed private
/// Store custody. Protocol admission is a bounded document operation under
/// its installed byte/node/depth ceilings, not a model dispatch or replay.
pub fn read_model_capture_bundle(
  wire : String,
  expected_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ModelCaptureBundleRead, RunEvidenceValueIssue] {
  let bundle = match
    admit_run_evidence_value(
      "model_capture_bundle", wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if bundle.identity != expected_cid {
    return Err(RunEvidenceIdentityMismatch)
  }
  guard @json.object_field(bundle.value, "captures")
    is Some(@json.Array(records)) else {
    return Err(RunEvidenceInvalidShape)
  }
  Ok({
    storage: { bundle: Some(bundle), records: Some(records), uses: 1, },
    released: false,
  })
}

///|
pub fn model_capture_bundle_identity(value : ModelCaptureBundleRead) -> String? {
  if value.released {
    None
  } else {
    value.storage.bundle.map(bundle => bundle.identity)
  }
}

///|
pub fn model_capture_bundle_count(value : ModelCaptureBundleRead) -> Int {
  if value.released {
    return -1
  }
  match value.storage.records {
    Some(records) => @json.array_count(records)
    None => -1
  }
}

///|
pub fn retain_model_capture_bundle_read(
  value : ModelCaptureBundleRead,
) -> ModelCaptureBundleRead? {
  if value.released ||
    value.storage.bundle is None ||
    value.storage.uses == 2147483647 {
    return None
  }
  value.storage.uses += 1
  Some({ storage: value.storage, released: false, })
}

///|
pub fn release_model_capture_bundle_read(
  value : ModelCaptureBundleRead,
) -> Bool {
  if value.released {
    return false
  }
  value.released = true
  value.storage.uses -= 1
  if value.storage.uses == 0 {
    value.storage.bundle = None
    value.storage.records = None
  }
  true
}

///|
/// Admit the flat invocation record separately. Response content is not
/// hashed here: the restoring owner traverses and validates it incrementally.
pub fn model_capture_bundle_record(
  value : ModelCaptureBundleRead,
  index : Int,
) -> Result[ModelCaptureRecordRead, RunEvidenceValueIssue] {
  guard !value.released &&
    value.storage.records is Some(records) &&
    @json.array_at(records, index) is Some(record) &&
    @json.object_field(record, "evidence") is Some(body) &&
    @json.object_field(record, "structured_response") is Some(response) else {
    return Err(RunEvidenceInvalidShape)
  }
  let evidence = match
    run_evidence_value(
      "model_invocation_evidence", "model_invocation_evidence_cid", body, 16384,
      1024, 16,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for name in ["model_call_slot_cid", "semantic_request_cid"] {
    if optional_string(@json.object_field(record, name)) !=
      optional_string(@json.object_field(evidence.value, name)) {
      return Err(RunEvidenceReferenceMismatch(name))
    }
  }
  Ok({ evidence, response, })
}

///|
pub fn model_capture_record_evidence(
  value : ModelCaptureRecordRead,
) -> RunEvidenceValue {
  value.evidence
}

///|
pub fn model_capture_record_response(
  value : ModelCaptureRecordRead,
) -> @json.CanonicalValue {
  value.response
}

///|
pub fn model_capture_record_text(
  value : ModelCaptureRecordRead,
  field : String,
) -> String? {
  optional_string(@json.object_field(value.evidence.value, field))
}

///|
pub fn model_capture_record_tokens(
  value : ModelCaptureRecordRead,
) -> (Int64, Int64)? {
  guard @json.object_field(value.evidence.value, "input_tokens")
    is Some(@json.Number(input)) &&
    @json.object_field(value.evidence.value, "output_tokens")
    is Some(@json.Number(output)) &&
    input >= 0.0 &&
    input < 9223372036854775808.0 &&
    output >= 0.0 &&
    output < 9223372036854775808.0 else {
    return None
  }
  Some((input.to_int64(), output.to_int64()))
}

///|
fn model_capture_optional_tokens(
  evidence : @json.CanonicalValue,
  field : String,
) -> Result[Int64?, RunEvidenceValueIssue] {
  match @json.object_field(evidence, field) {
    Some(@json.Null) => Ok(None)
    Some(@json.Number(value)) => {
      if value < 0.0 || value >= 9223372036854775808.0 {
        return Err(RunEvidenceInvalidShape)
      }
      let tokens = value.to_int64()
      if tokens.to_double() != value {
        return Err(RunEvidenceInvalidShape)
      }
      Ok(Some(tokens))
    }
    _ => Err(RunEvidenceInvalidShape)
  }
}

///|
/// Lift exact old/new records without fabricating absent usage or turning the
/// old writer's fixed stop into a provider-reported finish reason. The legacy
/// paired-token accessor remains unchanged; new callers use both independent
/// options here. This reader never invokes a provider or rehashes a response.
pub fn model_capture_record_observation(
  value : ModelCaptureRecordRead,
) -> Result[ModelCaptureObservation, RunEvidenceValueIssue] {
  let body = value.evidence.value
  let version = optional_string(@json.object_field(body, "version"))
  let historical = match version {
    Some("actql-model-invocation-evidence/0.1") => true
    Some("actql-model-invocation-evidence/0.2") => false
    _ => return Err(RunEvidenceInvalidShape)
  }
  guard optional_string(@json.object_field(body, "observed_at"))
    is Some(observed_at) else {
    return Err(RunEvidenceInvalidShape)
  }
  let input_tokens = match model_capture_optional_tokens(body, "input_tokens") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let output_tokens = match
    model_capture_optional_tokens(body, "output_tokens") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    origin: if historical {
      HistoricalAdmitted
    } else {
      Reported
    },
    provider_model: optional_string(
      @json.object_field(body, "provider_reported_model_id"),
    ),
    provider_revision: optional_string(
      @json.object_field(body, "provider_reported_revision"),
    ),
    provider_request_id: optional_string(
      @json.object_field(body, "provider_request_id"),
    ),
    gateway_request_id: optional_string(
      @json.object_field(body, "gateway_request_id"),
    ),
    input_tokens,
    output_tokens,
    provider_finish_reason: if historical {
      None
    } else {
      optional_string(@json.object_field(body, "finish_reason"))
    },
    historical_finish_reason: if historical {
      optional_string(@json.object_field(body, "finish_reason"))
    } else {
      None
    },
    response_profile_cid: optional_string(
      @json.object_field(body, "response_profile_cid"),
    ),
    response_complete: if historical {
      None
    } else {
      Some(true)
    },
    raw_response_artifact_cid: optional_string(
      @json.object_field(body, "raw_response_artifact_cid"),
    ),
    // Borrow the already admitted immutable subtree. Do not stringify, copy
    // or reinterpret unknown metadata as an execution or retry instruction.
    provider_metadata: match @json.object_field(body, "provider_metadata") {
      Some(metadata) if metadata is @json.Object(_) => Some(metadata)
      _ => None
    },
    observed_at,
  })
}
