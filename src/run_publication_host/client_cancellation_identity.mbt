///|
/// Identity only. Storage must retain the original operation outcome; neither
/// this handle nor replay authorizes sending, physical stop or resource release.
struct ClientCancellationIdentity {
  namespace_id : String
  authority_scope_cid : String
  cancel_id : String
  run_definition_cid : String
  expected_revision : Int
} derive(Eq, Debug)

///|
/// A stored fingerprint detects changed components on readmission. It is an
/// identity checksum, never evidence of storage provenance or authorization.
pub fn client_cancellation_intent_cid(
  value : ClientCancellationIdentity,
) -> String {
  let writer = @encode.writer(4096, 8, 1) catch {
    _ => abort("Invalid closed cancellation identity writer bounds")
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authority_scope_cid")
    @encode.string_value(writer, value.authority_scope_cid)
    @encode.key(writer, "cancel_id")
    @encode.string_value(writer, value.cancel_id)
    @encode.key(writer, "expected_revision")
    @encode.number_value(writer, value.expected_revision.to_double())
    @encode.key(writer, "namespace_id")
    @encode.string_value(writer, value.namespace_id)
    @encode.key(writer, "operation")
    @encode.string_value(writer, "cancel")
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, value.run_definition_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-client-host/0.1")
    @encode.end_object(writer)
    let wire = @encode.finish(writer)
    "sha256:" + @sha.hex(@utf8.encode(wire))
  } catch {
    _ => abort("Admitted cancellation identity exceeded its closed wire bounds")
  }
}

///|
pub(all) enum ClientCancellationIdentityIssue {
  InvalidScope
  InvalidOperationId
  InvalidRunDefinition
  InvalidRevision
} derive(Eq, Debug)

///|
pub(all) enum ClientCancellationIdentityRelation {
  DifferentOperation
  ChangedIntent
  SameOperation
} derive(Eq, Debug)

///|
fn valid_client_cancellation_text(value : String) -> Bool {
  if value.is_empty() || value.length() > 256 {
    return false
  }
  for index = 0; index < value.length(); index = index + 1 {
    let unit = value[index].to_int()
    if unit < 32 || unit == 127 {
      return false
    }
  }
  // The value writer rejects malformed Unicode without configuration NFC
  // normalization. The opaque operation key preserves every admitted unit.
  let writer = @encode.writer(4096, 1, 1) catch { _ => return false }
  try {
    @encode.string_value(writer, value)
    ignore(@encode.finish(writer))
  } catch {
    _ => return false
  }
  true
}

///|
/// Bind cancellation to one admitted Run and the caller's original control
/// revision. The journal checks that revision atomically with first admission.
pub fn prepare_client_cancellation_identity(
  namespace_id : String,
  authority_scope_cid : String,
  cancel_id : String,
  run_definition : @publication.PublicationContract,
  expected_revision : Int,
) -> Result[ClientCancellationIdentity, ClientCancellationIdentityIssue] {
  if !valid_client_cancellation_text(namespace_id) ||
    !valid_client_request_cid(authority_scope_cid) {
    return Err(InvalidScope)
  }
  if !valid_client_cancellation_text(cancel_id) {
    return Err(InvalidOperationId)
  }
  if @publication.publication_contract_name(run_definition) != "run_definition" {
    return Err(InvalidRunDefinition)
  }
  if expected_revision < 0 {
    return Err(InvalidRevision)
  }
  Ok({
    namespace_id,
    authority_scope_cid,
    cancel_id,
    run_definition_cid: @publication.publication_contract_identity(
      run_definition,
    ),
    expected_revision,
  })
}

///|
/// The key excludes target and revision: changing either under the same key
/// is a conflict, not a new cancellation. Stored outcomes remain immutable.
pub fn client_cancellation_identity_relation(
  requested : ClientCancellationIdentity,
  retained : ClientCancellationIdentity,
) -> ClientCancellationIdentityRelation {
  if requested.namespace_id != retained.namespace_id ||
    requested.authority_scope_cid != retained.authority_scope_cid ||
    requested.cancel_id != retained.cancel_id {
    return DifferentOperation
  }
  if requested.run_definition_cid != retained.run_definition_cid ||
    requested.expected_revision != retained.expected_revision {
    return ChangedIntent
  }
  SameOperation
}

///|
pub(all) enum ClientCancellationOperationAction {
  RecordCancellation(ClientRunCancellationAction)
  ReplayOriginalCancellation
} derive(Eq, Debug)

///|
pub(all) enum ClientCancellationOperationIssue {
  DifferentOperation
  ChangedIntent
  RevisionConflict
  AuthorizationDenied
  ForeignRunDefinition
} derive(Eq, Debug)

///|
/// Replay reads the recorded operation, never derives its original outcome
/// from today's Run flags. First admission reuses the existing Run Owner.
pub fn prepare_client_cancellation_operation(
  requested : ClientCancellationIdentity,
  retained : ClientCancellationIdentity?,
  run_definition : @publication.PublicationContract,
  current_revision : Int,
  current_authorization : Bool,
  terminal_observed : Bool,
  cancellation_requested : Bool,
) -> Result[ClientCancellationOperationAction, ClientCancellationOperationIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  if @publication.publication_contract_name(run_definition) != "run_definition" ||
    @publication.publication_contract_identity(run_definition) !=
    requested.run_definition_cid {
    return Err(ForeignRunDefinition)
  }
  if retained is Some(original) {
    return match client_cancellation_identity_relation(requested, original) {
      DifferentOperation => Err(DifferentOperation)
      ChangedIntent => Err(ChangedIntent)
      SameOperation => Ok(ReplayOriginalCancellation)
    }
  }
  if requested.expected_revision != current_revision {
    return Err(RevisionConflict)
  }
  match
    prepare_client_run_cancellation(
      run_definition,
      requested.run_definition_cid,
      current_authorization,
      terminal_observed,
      cancellation_requested,
    ) {
    Ok(AcceptCancellation) =>
      if current_revision == 2147483647 {
        Err(RevisionConflict)
      } else {
        Ok(RecordCancellation(AcceptCancellation))
      }
    Ok(action) => Ok(RecordCancellation(action))
    Err(AuthorizationDenied) => Err(AuthorizationDenied)
    Err(_) => Err(ForeignRunDefinition)
  }
}
