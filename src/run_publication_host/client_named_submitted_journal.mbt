///|
/// Original Journal index coordinates. These DATA issue neither a reference,
/// HMAC authentication, current authorization nor permission to prepare work.
pub struct ClientSubmittedNameKey {
  namespace_id : String
  actor : String
  name : String
} derive(Eq, Debug)

///|
/// Six original fields covered by the existing Journal epoch-key HMAC. The
/// physical Owner retains the authenticator and verifies it before resolution.
pub struct ClientSubmittedNameBinding {
  key : ClientSubmittedNameKey
  authority_scope_cid : String
  submission_id : String
  intent_cid : String
} derive(Eq, Debug)

///|
pub(all) enum ClientSubmittedNameIssue {
  InvalidName
  InvalidContext
  Encoding
  CapacityExceeded
  ChangedIntent
  CustodyLost
  OriginalUnavailable
} derive(Eq, Debug)

///|
fn submitted_name_context_text(value : String) -> Bool {
  if value.is_empty() || value.length() > 256 {
    return false
  }
  for ch in value.iter() {
    let code = ch.to_int()
    if code < 32 || code == 127 {
      return false
    }
  }
  // Encoding rejects ill-formed Unicode without normalizing the original.
  let writer = @encode.writer(8192, 1, 1) catch { _ => return false }
  try {
    @encode.string_value(writer, value)
    @encode.finish(writer) |> ignore
    true
  } catch {
    _ => false
  }
}

///|
/// Same caller-name domain as the original Submission nonce. The existing
/// logical scope Owner validates it; its CID is not published or used as an
/// index, epoch, permission, or replacement submission identity.
pub fn prepare_client_submitted_name_key(
  namespace_id : String,
  actor : String,
  name : String,
  authority_scope_cid : String,
) -> Result[ClientSubmittedNameKey, ClientSubmittedNameIssue] {
  if !submitted_name_context_text(namespace_id) ||
    !submitted_name_context_text(actor) ||
    !valid_client_request_cid(authority_scope_cid) {
    return Err(InvalidContext)
  }
  if @request_scope.prepare_logical_request_scope(
      authority_scope_cid, name, 256,
    )
    is Err(_) {
    return Err(InvalidName)
  }
  Ok({ namespace_id, actor, name, })
}

///|
pub fn client_submitted_name_key_fields(
  value : ClientSubmittedNameKey,
) -> (String, String, String) {
  (value.namespace_id, value.actor, value.name)
}

///|
pub fn prepare_client_submitted_name_binding(
  key : ClientSubmittedNameKey,
  authority_scope_cid : String,
  submission_id : String,
  intent_cid : String,
) -> Result[ClientSubmittedNameBinding, ClientSubmittedNameIssue] {
  if !valid_client_request_cid(authority_scope_cid) ||
    !valid_client_request_cid(submission_id) ||
    !valid_client_request_cid(intent_cid) {
    return Err(InvalidContext)
  }
  Ok({ key, authority_scope_cid, submission_id, intent_cid, })
}

///|
/// Exact existing private authentication preimage. This does not compute an
/// HMAC or admit a serialized row. The original physical Journal owns the key,
/// actual row, current/open checks, same transaction and confirmed COMMIT.
pub fn client_submitted_name_authentication_input(
  value : ClientSubmittedNameBinding,
  max_bytes : Int,
) -> Result[String, ClientSubmittedNameIssue] {
  let writer = @encode.writer(max_bytes, 8, 2) catch {
    _ => return Err(CapacityExceeded)
  }
  try {
    @encode.begin_array(writer)
    for
      text in [
        "scoped-submission-name",
        value.key.namespace_id,
        value.key.actor,
        value.key.name,
        value.authority_scope_cid,
        value.submission_id,
        value.intent_cid,
      ] {
      @encode.string_value(writer, text)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
/// Compare already authenticated original index/intent facts. The caller must
/// inspect the same transaction's name and intent custody before this phase,
/// verify the original row HMAC, then authenticate the returned original epoch
/// for lookup after this phase. Expiry is not renewed or interpreted here.
/// Missing/retired intent is unresolved; it never becomes an unused name.
pub fn inspect_client_named_submitted_original(
  expected_key : ClientSubmittedNameKey,
  authority_scope_cid : String,
  intent : ClientSubmittedIntent,
  binding : ClientSubmittedNameBinding,
  reference : ClientSubmissionReferenceRecord?,
  saved_intent : ClientSubmittedIntent?,
) -> Result[ClientSubmissionReferenceRecord, ClientSubmittedNameIssue] {
  if binding.key != expected_key {
    return Err(CustodyLost)
  }
  if binding.authority_scope_cid != authority_scope_cid ||
    binding.intent_cid != client_submitted_intent_cid(intent) {
    return Err(ChangedIntent)
  }
  guard reference is Some(reference) && saved_intent is Some(saved) else {
    return Err(OriginalUnavailable)
  }
  if client_submission_reference_record_request_id(reference) !=
    binding.submission_id ||
    client_submission_epoch_token_authority_scope_cid(reference.epoch) !=
    authority_scope_cid ||
    client_submitted_intent_cid(saved) != binding.intent_cid ||
    client_submitted_intent_wire(saved) != client_submitted_intent_wire(intent) {
    return Err(CustodyLost)
  }
  Ok(reference)
}
