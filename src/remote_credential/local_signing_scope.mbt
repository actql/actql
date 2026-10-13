///|
/// Pure identity metadata in the existing Credential Owner. Neither role,
/// copied CID, parsed grant nor use identity supplies signing permission or
/// opaque key custody. Native current authorization and durable use claiming
/// remain separate responsibilities of the existing Host/Credential Owners.
pub(all) enum LocalSigningPurpose {
  ReviewerProof
  HostAttestation
} derive(Eq, Debug)

///|
pub(all) struct LocalSigningCredentialScope {
  account_configuration_cid : String
  account_id : String
  attempt_id : String
  authority_scope_cid : String
  checkpoint_cid : String
  checkpoint_id : String
  checkpoint_kind : @checkpoint.CheckpointKind
  host_adoption_cid : String
  key_configuration_cid : String
  key_generation_cid : String
  key_id : String
  key_public_key_cid : String
  preimage : String
  principal : String
  request_cid : String
  request_scope_cid : String
  run_definition_cid : String
  run_invocation_cid : String
  submission_scope_cid : String
  unit_definition_cid : String
  purpose : LocalSigningPurpose
} derive(Eq, Debug)

///|
struct LocalSigningCredentialGrant {
  issuer_authority : String
  scope : LocalSigningCredentialScope
  expires_unix_ms : Int64
  max_uses : Int
  grant_cid : String
}

///|
fn local_signing_purpose_text(purpose : LocalSigningPurpose) -> String {
  match purpose {
    ReviewerProof => "reviewer_proof"
    HostAttestation => "host_attestation"
  }
}

///|
fn valid_local_signing_scope(scope : LocalSigningCredentialScope) -> Bool {
  valid_cid(scope.account_configuration_cid) &&
  valid_cid(scope.authority_scope_cid) &&
  valid_cid(scope.checkpoint_cid) &&
  valid_cid(scope.host_adoption_cid) &&
  valid_cid(scope.key_configuration_cid) &&
  valid_cid(scope.key_generation_cid) &&
  valid_cid(scope.key_public_key_cid) &&
  valid_cid(scope.request_cid) &&
  valid_cid(scope.request_scope_cid) &&
  valid_cid(scope.run_definition_cid) &&
  valid_cid(scope.run_invocation_cid) &&
  valid_cid(scope.submission_scope_cid) &&
  valid_cid(scope.unit_definition_cid) &&
  valid_cid(scope.preimage) &&
  bounded_text(scope.account_id, 512) &&
  bounded_text(scope.attempt_id, 256) &&
  bounded_text(scope.checkpoint_id, 256) &&
  bounded_text(scope.key_id, 512) &&
  bounded_text(scope.principal, 512)
}

///|
fn local_signing_credential_grant_body(
  grant : LocalSigningCredentialGrant,
) -> Result[String, RemoteCredentialIssue] {
  try {
    let writer = @encode.writer(32768, 64, 2)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "account_configuration_cid")
    @encode.string_value(writer, grant.scope.account_configuration_cid)
    @encode.ordered_key(writer, "account_id")
    @encode.string_value(writer, grant.scope.account_id)
    @encode.ordered_key(writer, "attempt_id")
    @encode.string_value(writer, grant.scope.attempt_id)
    @encode.ordered_key(writer, "authority_scope_cid")
    @encode.string_value(writer, grant.scope.authority_scope_cid)
    @encode.ordered_key(writer, "checkpoint_cid")
    @encode.string_value(writer, grant.scope.checkpoint_cid)
    @encode.ordered_key(writer, "checkpoint_id")
    @encode.string_value(writer, grant.scope.checkpoint_id)
    @encode.ordered_key(writer, "checkpoint_kind")
    @encode.string_value(
      writer,
      @checkpoint.checkpoint_kind_token(grant.scope.checkpoint_kind),
    )
    @encode.ordered_key(writer, "expires_unix_ms")
    @encode.string_value(writer, grant.expires_unix_ms.to_string())
    @encode.ordered_key(writer, "host_adoption_cid")
    @encode.string_value(writer, grant.scope.host_adoption_cid)
    @encode.ordered_key(writer, "issuer_authority")
    @encode.string_value(writer, grant.issuer_authority)
    @encode.ordered_key(writer, "key_configuration_cid")
    @encode.string_value(writer, grant.scope.key_configuration_cid)
    @encode.ordered_key(writer, "key_generation_cid")
    @encode.string_value(writer, grant.scope.key_generation_cid)
    @encode.ordered_key(writer, "key_id")
    @encode.string_value(writer, grant.scope.key_id)
    @encode.ordered_key(writer, "key_public_key_cid")
    @encode.string_value(writer, grant.scope.key_public_key_cid)
    @encode.ordered_key(writer, "max_uses")
    @encode.number_value(writer, grant.max_uses.to_double())
    @encode.ordered_key(writer, "preimage")
    @encode.string_value(writer, grant.scope.preimage)
    @encode.ordered_key(writer, "principal")
    @encode.string_value(writer, grant.scope.principal)
    @encode.ordered_key(writer, "purpose")
    @encode.string_value(
      writer,
      local_signing_purpose_text(grant.scope.purpose),
    )
    @encode.ordered_key(writer, "request_cid")
    @encode.string_value(writer, grant.scope.request_cid)
    @encode.ordered_key(writer, "request_scope_cid")
    @encode.string_value(writer, grant.scope.request_scope_cid)
    @encode.ordered_key(writer, "run_definition_cid")
    @encode.string_value(writer, grant.scope.run_definition_cid)
    @encode.ordered_key(writer, "run_invocation_cid")
    @encode.string_value(writer, grant.scope.run_invocation_cid)
    @encode.ordered_key(writer, "submission_scope_cid")
    @encode.string_value(writer, grant.scope.submission_scope_cid)
    @encode.ordered_key(writer, "unit_definition_cid")
    @encode.string_value(writer, grant.scope.unit_definition_cid)
    @encode.ordered_key(writer, "version")
    @encode.string_value(writer, "actql-local-signing-credential-grant/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidCredentialGrant)
  }
}

///|
/// Prepare only a finite signing identity, never a current Allow, a key
/// projection, a durable claim or a signature. Exact preimage text must come
/// from the original Checkpoint Owner at the operational boundary.
pub fn prepare_local_signing_credential_grant(
  issuer_authority : String,
  scope : LocalSigningCredentialScope,
  expires_unix_ms : Int64,
  max_uses : Int,
) -> Result[LocalSigningCredentialGrant, RemoteCredentialIssue] {
  if !bounded_text(issuer_authority, 512) ||
    !valid_local_signing_scope(scope) ||
    expires_unix_ms <= 0L ||
    max_uses < 1 ||
    max_uses > 1024 {
    return Err(InvalidCredentialGrant)
  }
  let pending : LocalSigningCredentialGrant = {
    issuer_authority,
    scope,
    expires_unix_ms,
    max_uses,
    grant_cid: "pending",
  }
  let body = match local_signing_credential_grant_body(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @sha.text_hex(body)
  .map(cid => { ..pending, grant_cid: "sha256:" + cid, })
  .map_err(_ => InvalidCredentialGrant)
}

///|
pub fn local_signing_credential_grant_json(
  grant : LocalSigningCredentialGrant,
) -> Result[String, RemoteCredentialIssue] {
  let body = match local_signing_credential_grant_body(grant) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let cid = match @sha.text_hex(body) {
    Ok(value) => "sha256:" + value
    Err(_) => return Err(InvalidCredentialGrant)
  }
  if cid != grant.grant_cid {
    Err(CredentialGrantIdentityMismatch)
  } else {
    Ok(body)
  }
}

///|
pub fn local_signing_credential_grant_cid(
  grant : LocalSigningCredentialGrant,
) -> String {
  grant.grant_cid
}

///|
pub fn local_signing_credential_grant_scope(
  grant : LocalSigningCredentialGrant,
) -> LocalSigningCredentialScope {
  grant.scope
}

///|
pub fn admit_local_signing_credential_grant_json(
  body : String,
  claimed_grant_cid : String,
) -> Result[LocalSigningCredentialGrant, RemoteCredentialIssue] {
  try {
    let source = match
      @source.parse_json_bytes_preserving(@utf8.encode(body), {
        max_input_bytes: 32768,
        max_nodes: 64,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise RemoteCredentialDecodeStop
    }
    let cursor = credential_decoded(
      @decode.admit(source, {
        max_nodes: 64,
        max_depth: 2,
        max_string_bytes: 32768,
        max_total_string_bytes: 32768,
      }),
    )
    let object = credential_decoded(
      @decode.closed_object(cursor, [
        "account_configuration_cid", "account_id", "attempt_id", "authority_scope_cid",
        "checkpoint_cid", "checkpoint_id", "checkpoint_kind", "expires_unix_ms",
        "host_adoption_cid", "issuer_authority", "key_configuration_cid", "key_generation_cid",
        "key_id", "key_public_key_cid", "max_uses", "preimage", "principal", "purpose",
        "request_cid", "request_scope_cid", "run_definition_cid", "run_invocation_cid",
        "submission_scope_cid", "unit_definition_cid", "version",
      ]),
    )
    if credential_text(object, "version") !=
      "actql-local-signing-credential-grant/0.1" {
      return Err(InvalidCredentialGrant)
    }
    let purpose = match credential_text(object, "purpose") {
      "reviewer_proof" => ReviewerProof
      "host_attestation" => HostAttestation
      _ => return Err(InvalidCredentialGrant)
    }
    guard @checkpoint.parse_checkpoint_kind(
        credential_text(object, "checkpoint_kind"),
      )
      is Some(checkpoint_kind) else {
      return Err(InvalidCredentialGrant)
    }
    let scope : LocalSigningCredentialScope = {
      account_configuration_cid: credential_text(
        object, "account_configuration_cid",
      ),
      account_id: credential_text(object, "account_id"),
      attempt_id: credential_text(object, "attempt_id"),
      authority_scope_cid: credential_text(object, "authority_scope_cid"),
      checkpoint_cid: credential_text(object, "checkpoint_cid"),
      checkpoint_id: credential_text(object, "checkpoint_id"),
      checkpoint_kind,
      host_adoption_cid: credential_text(object, "host_adoption_cid"),
      key_configuration_cid: credential_text(object, "key_configuration_cid"),
      key_generation_cid: credential_text(object, "key_generation_cid"),
      key_id: credential_text(object, "key_id"),
      key_public_key_cid: credential_text(object, "key_public_key_cid"),
      preimage: credential_text(object, "preimage"),
      principal: credential_text(object, "principal"),
      request_cid: credential_text(object, "request_cid"),
      request_scope_cid: credential_text(object, "request_scope_cid"),
      run_definition_cid: credential_text(object, "run_definition_cid"),
      run_invocation_cid: credential_text(object, "run_invocation_cid"),
      submission_scope_cid: credential_text(object, "submission_scope_cid"),
      unit_definition_cid: credential_text(object, "unit_definition_cid"),
      purpose,
    }
    let grant = match
      prepare_local_signing_credential_grant(
        credential_text(object, "issuer_authority"),
        scope,
        credential_int64_text(credential_text(object, "expires_unix_ms")),
        credential_int(object, "max_uses"),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if local_signing_credential_grant_json(grant) != Ok(body) {
      return Err(InvalidCredentialGrant)
    }
    if grant.grant_cid != claimed_grant_cid {
      return Err(CredentialGrantIdentityMismatch)
    }
    Ok(grant)
  } catch {
    RemoteCredentialDecodeStop => Err(InvalidCredentialGrant)
  }
}
