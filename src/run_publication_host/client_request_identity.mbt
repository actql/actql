///|
/// Identity of one logical Client request before physical Run admission.
/// The two CIDs contain no Run, Site, worker, attempt or wall-clock identity.
struct ClientRequestIdentity {
  authority_scope_cid : String
  caller_request_id : String
  scope : @request_scope.LogicalRequestScope
  intent_fingerprint_cid : String
  program_definition_cid : String
  parameter_values_cid : String
  caller_input_intent_cid : String
} derive(Eq, Debug)

///|
pub fn client_request_authority_scope_cid(
  value : ClientRequestIdentity,
) -> String {
  value.authority_scope_cid
}

///|
pub fn client_request_caller_id(value : ClientRequestIdentity) -> String {
  value.caller_request_id
}

///|
pub fn client_request_scope_cid(value : ClientRequestIdentity) -> String {
  @request_scope.logical_request_scope_cid(value.scope)
}

///|
/// Reuse the exact logical scope issued or re-admitted with Client intent.
/// This transfers identity, not current authorization or a mutation permit.
pub fn client_request_logical_scope(
  value : ClientRequestIdentity,
) -> @request_scope.LogicalRequestScope {
  value.scope
}

///|
/// An Effect caller may not pair a checked Program with another request's
/// checked intent. Current authority and durable request admission remain
/// Host obligations before execution.
pub fn prepared_client_effect_request_scope(
  prepared : PreparedClientEffectComputation,
  request : ClientRequestIdentity,
) -> Result[@request_scope.LogicalRequestScope, ClientRequestIdentityIssue] {
  let identity = prepared_client_effect_identity(prepared)
  if identity.program_definition_cid != request.program_definition_cid ||
    identity.parameter_values_cid != request.parameter_values_cid {
    return Err(IdentityMismatch)
  }
  Ok(request.scope)
}

///|
pub fn client_request_intent_cid(value : ClientRequestIdentity) -> String {
  value.intent_fingerprint_cid
}

///|
pub fn client_request_program_cid(value : ClientRequestIdentity) -> String {
  value.program_definition_cid
}

///|
pub fn client_request_parameters_cid(value : ClientRequestIdentity) -> String {
  value.parameter_values_cid
}

///|
pub fn client_request_input_cid(value : ClientRequestIdentity) -> String {
  value.caller_input_intent_cid
}

///|
pub(all) enum ClientRequestIdentityIssue {
  InvalidAuthorityScope
  InvalidRequestId
  InvalidInputIntent
  InvalidCheckedIdentity
  IdentityMismatch
  Encoding
} derive(Eq, Debug)

///|
pub(all) enum ClientRequestIdentityRelation {
  DifferentRequest
  SameRequest
  ChangedIntent
} derive(Eq, Debug)

///|
/// A relation between two owner-verified identities. A different logical key
/// is another request; a matching key with changed intent must never dispatch.
pub fn client_request_identity_relation(
  requested : ClientRequestIdentity,
  retained : ClientRequestIdentity,
) -> ClientRequestIdentityRelation {
  if requested.authority_scope_cid != retained.authority_scope_cid ||
    requested.caller_request_id != retained.caller_request_id ||
    requested.scope != retained.scope {
    return DifferentRequest
  }
  if requested.intent_fingerprint_cid != retained.intent_fingerprint_cid ||
    requested.program_definition_cid != retained.program_definition_cid ||
    requested.parameter_values_cid != retained.parameter_values_cid ||
    requested.caller_input_intent_cid != retained.caller_input_intent_cid {
    return ChangedIntent
  }
  SameRequest
}

///|
fn valid_client_request_cid(value : String) -> Bool {
  value.has_prefix("sha256:") && valid_sha256_hex_from(value, 7)
}

///|
fn valid_sha256_hex_from(value : String, start : Int) -> Bool {
  if value.length() != start + 64 {
    return false
  }
  for index = start; index < value.length(); index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
/// The only 0.1 source-free caller input intent. An explicitly selected empty
/// input is a different intent and must not use this identity.
pub fn source_free_caller_input_intent_cid() -> String {
  "sha256:" +
  @sha.hex(
    @utf8.encode(
      "{\"selection\":\"none\",\"version\":\"actql-caller-input-intent/0.1\"}",
    ),
  )
}

///|
pub fn prepare_source_free_client_request_identity(
  prepared : PreparedClientProgram,
  authority_scope_cid : String,
  caller_request_id : String,
) -> Result[ClientRequestIdentity, ClientRequestIdentityIssue] {
  prepare_client_request_identity(
    prepared,
    authority_scope_cid,
    caller_request_id,
    source_free_caller_input_intent_cid(),
  )
}

///|
pub fn admit_source_free_client_request_identity_record(
  authority_scope_cid : String,
  caller_request_id : String,
  program_definition_cid : String,
  parameter_values_cid : String,
  caller_input_intent_cid : String,
  logical_request_scope_cid : String,
  intent_fingerprint_cid : String,
) -> Result[ClientRequestIdentity, ClientRequestIdentityIssue] {
  if caller_input_intent_cid != source_free_caller_input_intent_cid() {
    return Err(InvalidInputIntent)
  }
  admit_client_request_identity_record(
    authority_scope_cid, caller_request_id, program_definition_cid, parameter_values_cid,
    caller_input_intent_cid, logical_request_scope_cid, intent_fingerprint_cid,
  )
}

///|
/// Compute the closed logical request key and immutable checked intent.
/// Physical storage must still atomically bind this identity to exactly one
/// owner-issued Run record before dispatch; this function performs no I/O.
pub fn prepare_client_request_identity(
  prepared : PreparedClientProgram,
  authority_scope_cid : String,
  caller_request_id : String,
  caller_input_intent_cid : String,
) -> Result[ClientRequestIdentity, ClientRequestIdentityIssue] {
  derive_client_request_identity(
    prepared_client_identity(prepared),
    authority_scope_cid,
    caller_request_id,
    caller_input_intent_cid,
  )
}

///|
/// Effectful requests use the same logical key and checked intent law as
/// Effect-free requests. The static Effect closure remains attached to this
/// owner; no Preview or apply authority is inferred from the request key.
pub fn prepare_client_effect_request_identity(
  prepared : PreparedClientEffectComputation,
  authority_scope_cid : String,
  caller_request_id : String,
  caller_input_intent_cid : String,
) -> Result[ClientRequestIdentity, ClientRequestIdentityIssue] {
  derive_client_request_identity(
    prepared_client_effect_identity(prepared),
    authority_scope_cid,
    caller_request_id,
    caller_input_intent_cid,
  )
}

///|
/// Derive the Request from the original input retained by this checked Effect.
/// A caller with an authenticated Submission also supplies its expected input
/// CID. Only the same retained input can satisfy that expectation.
pub fn prepare_client_original_effect_request_identity(
  prepared : PreparedClientEffectComputation,
  authority_scope_cid : String,
  caller_request_id : String,
  submitted_input_cid? : String? = None,
) -> Result[ClientRequestIdentity, ClientRequestIdentityIssue] {
  let input = client_effect_original_input_intent_cid(prepared)
  if submitted_input_cid is Some(expected) &&
    !(prepared.source_intent is Some(_) && input == expected) {
    return Err(IdentityMismatch)
  }
  prepare_client_effect_request_identity(
    prepared, authority_scope_cid, caller_request_id, input,
  )
}

///|
/// Exact input identity from an independently retained Submission and Run.
/// This holds no authored body and grants no current permission or authority.
struct ClientEffectRetainedSubmissionInput {
  request : ClientRequestIdentity
  run_definition_cid : String
} derive(Eq)

///|
/// The Host must already have authenticated the same submitted original and
/// Run. Only a Request which explicitly binds that input can use this proof.
pub fn prepare_client_effect_retained_submission_input(
  reference : ClientSubmissionReferenceRecord,
  intent : ClientSubmittedIntent,
  request : ClientRequestIdentity,
  run_definition_cid : String,
) -> Result[ClientEffectRetainedSubmissionInput, ClientRequestIdentityIssue] {
  if !client_submission_reference_matches_request(reference, request) ||
    !valid_client_request_cid(run_definition_cid) ||
    client_submitted_intent_requests_read_only(intent) ||
    request.caller_input_intent_cid == source_free_caller_input_intent_cid() ||
    request.caller_input_intent_cid != client_submitted_intent_cid(intent) {
    return Err(IdentityMismatch)
  }
  Ok({ request, run_definition_cid, })
}

///|
/// Readmission checks stored identity components against both claimed CIDs.
/// It verifies identity, not the storage provenance or current authorization.
pub fn admit_client_request_identity_record(
  authority_scope_cid : String,
  caller_request_id : String,
  program_definition_cid : String,
  parameter_values_cid : String,
  caller_input_intent_cid : String,
  logical_request_scope_cid : String,
  intent_fingerprint_cid : String,
) -> Result[ClientRequestIdentity, ClientRequestIdentityIssue] {
  let admitted = match
    derive_client_request_identity(
      { program_definition_cid, parameter_values_cid, },
      authority_scope_cid,
      caller_request_id,
      caller_input_intent_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if client_request_scope_cid(admitted) != logical_request_scope_cid ||
    admitted.intent_fingerprint_cid != intent_fingerprint_cid {
    return Err(IdentityMismatch)
  }
  Ok(admitted)
}

///|
fn derive_client_request_identity(
  checked : ClientProgramIdentity,
  authority_scope_cid : String,
  caller_request_id : String,
  caller_input_intent_cid : String,
) -> Result[ClientRequestIdentity, ClientRequestIdentityIssue] {
  if !valid_client_request_cid(authority_scope_cid) {
    return Err(InvalidAuthorityScope)
  }
  if !valid_client_request_cid(caller_input_intent_cid) {
    return Err(InvalidInputIntent)
  }
  if !valid_client_request_cid(checked.program_definition_cid) ||
    !valid_client_request_cid(checked.parameter_values_cid) {
    return Err(InvalidCheckedIdentity)
  }
  let scope = match
    @request_scope.prepare_logical_request_scope(
      authority_scope_cid, caller_request_id, 256,
    ) {
    Ok(value) => value
    Err(InvalidAuthorityScope) => return Err(InvalidAuthorityScope)
    Err(InvalidCallerRequest) => return Err(InvalidRequestId)
    Err(InvalidLimits) | Err(Encoding) => return Err(Encoding)
  }
  let intent_writer = @encode.writer(1024, 5, 1) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(intent_writer)
    @encode.key(intent_writer, "caller_input_intent_cid")
    @encode.string_value(intent_writer, caller_input_intent_cid)
    @encode.key(intent_writer, "parameter_values_cid")
    @encode.string_value(intent_writer, checked.parameter_values_cid)
    @encode.key(intent_writer, "program_definition_cid")
    @encode.string_value(intent_writer, checked.program_definition_cid)
    @encode.key(intent_writer, "version")
    @encode.string_value(intent_writer, "actql-logical-request-intent/0.1")
    @encode.end_object(intent_writer)
  } catch {
    _ => return Err(Encoding)
  }
  let intent = @encode.finish(intent_writer) catch { _ => return Err(Encoding) }
  Ok({
    authority_scope_cid,
    caller_request_id,
    scope,
    intent_fingerprint_cid: "sha256:" + @sha.hex(@utf8.encode(intent)),
    // This logical identity survives retirement of its checked payload.
    // Own only these two already validated, fixed-length CID strings in the
    // constructor's lifetime; never retain that payload's native allocation.
    // This copies DATA, not a preparation, Request, issuer or permission.
    program_definition_cid: String::from_array(
      checked.program_definition_cid.to_array(),
    ),
    parameter_values_cid: String::from_array(
      checked.parameter_values_cid.to_array(),
    ),
    caller_input_intent_cid,
  })
}

///|
/// Derive identity from a single nominal Submission snapshot. The caller
/// retains the same physical Read and must have checked this snapshot's intent
/// under its independently validated authority scope.
pub fn prepare_client_submitted_effect_request_identity(
  prepared : PreparedClientEffectComputation,
  authority_scope_cid : String,
  snapshot : ClientSavedSubmissionSnapshot,
) -> Result[ClientRequestIdentity, ClientRequestIdentityIssue] {
  let original = client_saved_submission_record(snapshot)
  let reference = original.reference
  if client_submission_epoch_token_authority_scope_cid(
      client_submission_reference_record_epoch(reference),
    ) !=
    authority_scope_cid {
    return Err(IdentityMismatch)
  }
  prepare_client_effect_request_identity(
    prepared,
    authority_scope_cid,
    client_submission_reference_record_request_id(reference),
    client_submitted_intent_cid(original.intent),
  )
}

///|
/// Backing of the fixed Request constructor alone. Its authority, request and
/// input CIDs stay borrowed. The two copied checked CIDs and the two issued
/// CIDs remain live; bounded validation, canonical writers and hash are scratch.
pub fn client_request_identity_construction_inventory() -> (
  @execution.PreparationRepresentationUnits,
  @execution.PreparationRepresentationUnits,
)? {
  let scope = @request_scope.logical_request_scope_construction_inventory()
  guard @encode.text_writer_construction_inventory(1024, 5, 1) is Some(intent) &&
    @encode.hash_writer_construction_inventory(0, 0) is Some(hash) else {
    return None
  }
  Some(
    (
      {
        record_headers: 6L,
        reference_slots: 12L,
        scalar_words: 0L,
        owned_utf16_units: 284L,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: scope.record_headers +
        intent.record_headers +
        hash.record_headers +
        4L,
        reference_slots: scope.reference_slots +
        intent.reference_slots +
        hash.reference_slots,
        scalar_words: scope.scalar_words +
        intent.scalar_words +
        hash.scalar_words +
        142L,
        owned_utf16_units: scope.owned_utf16_units +
        intent.owned_utf16_units +
        hash.owned_utf16_units,
        owned_wire_bytes: scope.owned_wire_bytes + hash.owned_wire_bytes + 1024L,
      },
    ),
  )
}
