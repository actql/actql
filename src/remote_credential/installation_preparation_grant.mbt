///|
/// Runless installation metadata scope DATA. The complete original subject is
/// retained, not reconstructed from its CID. The installation Owner separately
/// retains its actual Host/request/Site/credential originals and currentness.
pub(all) struct InstallationPreparationCredentialScope {
  subject : InstallationPreparationSubject
  metadata_occurrence_id : String
  operation : String
  request_body_cid : String
  request_method : String
  request_path : String
  resource_origin : String
} derive(Eq, Debug)

///|
struct InstallationPreparationCredentialGrant {
  issuer_authority : String
  scope : InstallationPreparationCredentialScope
  expires_unix_ms : Int64
  max_uses : Int
  identity : String
}

///|
/// Admit scope DATA without issuing operational installation custody.
pub fn admit_installation_preparation_credential_scope(
  scope : InstallationPreparationCredentialScope,
) -> Result[InstallationPreparationCredentialScope, RemoteCredentialIssue] {
  if installation_preparation_scope_valid(scope) {
    Ok(scope)
  } else {
    Err(InvalidCredentialGrant)
  }
}

///|
fn installation_preparation_scope_valid(
  scope : InstallationPreparationCredentialScope,
) -> Bool {
  installation_preparation_subject_fields_valid(scope.subject.fields) &&
  installation_preparation_text(scope.metadata_occurrence_id, 512) &&
  installation_preparation_text(scope.operation, 512) &&
  scope.request_method == "GET" &&
  installation_preparation_text(scope.request_path, 2048) &&
  scope.request_path.has_prefix("/") &&
  !scope.request_path.has_prefix("//") &&
  !scope.request_path.contains("?") &&
  !scope.request_path.contains("#") &&
  !scope.request_path.contains("\r") &&
  !scope.request_path.contains("\n") &&
  valid_origin(scope.resource_origin) &&
  scope.resource_origin.length() > 8 &&
  !scope.resource_origin[8:].contains("/") &&
  !scope.resource_origin.contains("@") &&
  !scope.resource_origin.contains(" ") &&
  !scope.resource_origin.contains("\r") &&
  !scope.resource_origin.contains("\n") &&
  !scope.resource_origin.contains("\u{0}") &&
  scope.request_body_cid ==
  "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}

///|
fn installation_preparation_grant_body(
  grant : InstallationPreparationCredentialGrant,
) -> Result[String, RemoteCredentialIssue] {
  Ok(emit_installation_preparation_grant_body(grant)) catch {
    _ => Err(InvalidCredentialGrant)
  }
}

///|
fn emit_installation_preparation_grant_body(
  grant : InstallationPreparationCredentialGrant,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(16384, 32, 2)
  @encode.begin_ordered_object(writer)
  @encode.ordered_key(writer, "expires_unix_ms")
  @encode.string_value(writer, grant.expires_unix_ms.to_string())
  @encode.ordered_key(writer, "issuer_authority")
  @encode.string_value(writer, grant.issuer_authority)
  @encode.ordered_key(writer, "max_uses")
  @encode.number_value(writer, grant.max_uses.to_double())
  for
    (key, value) in [
      ("metadata_occurrence_id", grant.scope.metadata_occurrence_id),
      ("operation", grant.scope.operation),
      ("preparation_subject_cid", grant.scope.subject.identity),
      ("request_body_cid", grant.scope.request_body_cid),
      ("request_method", grant.scope.request_method),
      ("request_path", grant.scope.request_path),
      ("resource_origin", grant.scope.resource_origin),
      ("subject_kind", "installation_metadata"),
      ("version", "actql-installation-preparation-credential-grant/0.1"),
    ] {
    @encode.ordered_key(writer, key)
    @encode.string_value(writer, value)
  }
  @encode.end_object(writer)
  @encode.finish(writer)
}

///|
/// Pure bounded identity construction. This is not an issuer/current Account
/// decision, operational preparation, funding, durable claim or I/O permission.
/// The registered metadata occurrence must independently admit the operation
/// and exact dependent target; this function does not classify Provider APIs.
pub fn prepare_installation_preparation_credential_grant(
  issuer_authority : String,
  scope : InstallationPreparationCredentialScope,
  expires_unix_ms : Int64,
  max_uses : Int,
) -> Result[InstallationPreparationCredentialGrant, RemoteCredentialIssue] {
  if !installation_preparation_text(issuer_authority, 512) ||
    !installation_preparation_scope_valid(scope) ||
    expires_unix_ms <= 0L ||
    max_uses <= 0 ||
    max_uses > 1024 {
    return Err(InvalidCredentialGrant)
  }
  let pending : InstallationPreparationCredentialGrant = {
    issuer_authority,
    scope,
    expires_unix_ms,
    max_uses,
    identity: "pending",
  }
  let body = match installation_preparation_grant_body(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @sha.text_hex(body)
  .map(digest => { ..pending, identity: "sha256:" + digest, })
  .map_err(_ => InvalidCredentialGrant)
}

///|
pub fn InstallationPreparationCredentialGrant::original_wire(
  self : InstallationPreparationCredentialGrant,
) -> Result[String, RemoteCredentialIssue] {
  installation_preparation_grant_body(self)
}

///|
pub fn InstallationPreparationCredentialGrant::cid(
  self : InstallationPreparationCredentialGrant,
) -> String {
  self.identity
}

///|
pub fn InstallationPreparationCredentialGrant::scope(
  self : InstallationPreparationCredentialGrant,
) -> InstallationPreparationCredentialScope {
  self.scope
}

///|
pub fn InstallationPreparationCredentialGrant::issuer_authority(
  self : InstallationPreparationCredentialGrant,
) -> String {
  self.issuer_authority
}

///|
pub fn InstallationPreparationCredentialGrant::expires_unix_ms(
  self : InstallationPreparationCredentialGrant,
) -> Int64 {
  self.expires_unix_ms
}

///|
pub fn InstallationPreparationCredentialGrant::max_uses(
  self : InstallationPreparationCredentialGrant,
) -> Int {
  self.max_uses
}

///|
/// Admit only this closed subject alternative, retaining the supplied original
/// subject. Neither the CID nor restored DATA reissues operational custody.
pub fn admit_installation_preparation_credential_grant_json(
  subject : InstallationPreparationSubject,
  body : String,
  expected_cid : String,
) -> Result[InstallationPreparationCredentialGrant, RemoteCredentialIssue] {
  if body.length() > 16384 {
    return Err(InvalidCredentialGrant)
  }
  try {
    let source = match
      @source.parse_json_bytes_preserving(@utf8.encode(body), {
        max_input_bytes: 16384,
        max_nodes: 32,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise RemoteCredentialDecodeStop
    }
    let object = credential_decoded(
      @decode.closed_object(
        credential_decoded(
          @decode.admit(source, {
            max_nodes: 32,
            max_depth: 2,
            max_string_bytes: 6144,
            max_total_string_bytes: 16384,
          }),
        ),
        [
          "expires_unix_ms", "issuer_authority", "max_uses", "metadata_occurrence_id",
          "operation", "preparation_subject_cid", "request_body_cid", "request_method",
          "request_path", "resource_origin", "subject_kind", "version",
        ],
      ),
    )
    if credential_text(object, "version") !=
      "actql-installation-preparation-credential-grant/0.1" ||
      credential_text(object, "subject_kind") != "installation_metadata" ||
      credential_text(object, "preparation_subject_cid") != subject.identity {
      return Err(InvalidCredentialGrant)
    }
    let grant = match
      prepare_installation_preparation_credential_grant(
        credential_text(object, "issuer_authority"),
        {
          subject,
          metadata_occurrence_id: credential_text(
            object, "metadata_occurrence_id",
          ),
          operation: credential_text(object, "operation"),
          request_body_cid: credential_text(object, "request_body_cid"),
          request_method: credential_text(object, "request_method"),
          request_path: credential_text(object, "request_path"),
          resource_origin: credential_text(object, "resource_origin"),
        },
        credential_int64_text(credential_text(object, "expires_unix_ms")),
        credential_int(object, "max_uses"),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if grant.original_wire() != Ok(body) {
      Err(InvalidCredentialGrant)
    } else if grant.identity != expected_cid {
      Err(CredentialGrantIdentityMismatch)
    } else {
      Ok(grant)
    }
  } catch {
    RemoteCredentialDecodeStop => Err(InvalidCredentialGrant)
  }
}

///|
fn installation_preparation_scope_matches(
  original : InstallationPreparationCredentialScope,
  actual : InstallationPreparationCredentialScope,
) -> Bool {
  physical_equal(original.subject, actual.subject) && original == actual
}
