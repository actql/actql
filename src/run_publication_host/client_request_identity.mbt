///|
/// Identity of one logical Client request before physical Run admission.
/// The two CIDs contain no Run, Site, worker, attempt or wall-clock identity.
struct ClientRequestIdentity {
  authority_scope_cid : String
  caller_request_id : String
  logical_request_scope_cid : String
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
  value.logical_request_scope_cid
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
    requested.logical_request_scope_cid != retained.logical_request_scope_cid {
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
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
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
  if admitted.logical_request_scope_cid != logical_request_scope_cid ||
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
    @request_scope.prepare_scope_cid(
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
    logical_request_scope_cid: scope,
    intent_fingerprint_cid: "sha256:" + @sha.hex(@utf8.encode(intent)),
    program_definition_cid: checked.program_definition_cid,
    parameter_values_cid: checked.parameter_values_cid,
    caller_input_intent_cid,
  })
}
