///|
struct InstallationPreparationCredentialUse {
  grant : InstallationPreparationCredentialGrant
  use_id : String
  ordinal : Int
  identity : String
}

///|
fn installation_preparation_use_body(
  value : InstallationPreparationCredentialUse,
) -> Result[String, RemoteCredentialIssue] {
  credential_use_record_body(
    value.grant.identity,
    value.use_id,
    value.ordinal,
    "actql-remote-credential-use/0.1",
  )
}

///|
/// Retain the same original subject and exact operation occurrence. Used count,
/// clock and revocation are observations of the existing physical journal/Owner;
/// this pure check does not claim an ordinal or establish current authority.
pub fn prepare_installation_preparation_credential_use(
  grant : InstallationPreparationCredentialGrant,
  use_id : String,
  trusted_now_ms : Int64,
  used_count : Int,
  revoked : Bool,
  actual : InstallationPreparationCredentialScope,
) -> Result[InstallationPreparationCredentialUse, RemoteCredentialIssue] {
  if !installation_preparation_text(use_id, 256) ||
    trusted_now_ms < 0L ||
    trusted_now_ms >= grant.expires_unix_ms ||
    used_count < 0 ||
    used_count >= grant.max_uses ||
    revoked ||
    !installation_preparation_scope_matches(grant.scope, actual) {
    return Err(CredentialGrantInactive)
  }
  let pending : InstallationPreparationCredentialUse = {
    grant,
    use_id,
    ordinal: used_count + 1,
    identity: "pending",
  }
  let body = match installation_preparation_use_body(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @sha.text_hex(body)
  .map(digest => { ..pending, identity: "sha256:" + digest, })
  .map_err(_ => InvalidCredentialGrant)
}

///|
pub fn InstallationPreparationCredentialUse::cid(
  self : InstallationPreparationCredentialUse,
) -> String {
  self.identity
}

///|
pub fn InstallationPreparationCredentialUse::original_wire(
  self : InstallationPreparationCredentialUse,
) -> Result[String, RemoteCredentialIssue] {
  installation_preparation_use_body(self)
}

///|
pub fn InstallationPreparationCredentialUse::projection(
  self : InstallationPreparationCredentialUse,
) -> (String, String, String, Int) {
  (self.identity, self.grant.identity, self.use_id, self.ordinal)
}

///|
pub fn authorize_installation_preparation_credential_use(
  value : InstallationPreparationCredentialUse,
  trusted_now_ms : Int64,
  revoked : Bool,
  actual : InstallationPreparationCredentialScope,
) -> Result[Unit, RemoteCredentialIssue] {
  if trusted_now_ms < 0L ||
    trusted_now_ms >= value.grant.expires_unix_ms ||
    revoked ||
    !installation_preparation_scope_matches(value.grant.scope, actual) {
    Err(CredentialGrantInactive)
  } else {
    Ok(())
  }
}

///|
/// Cold DATA admission retains the supplied grant but does not consume a use,
/// recover a live request, clear Unknown or provide permission to resend it.
pub fn admit_installation_preparation_credential_use_json(
  grant : InstallationPreparationCredentialGrant,
  body : String,
  expected_cid : String,
) -> Result[InstallationPreparationCredentialUse, RemoteCredentialIssue] {
  try {
    let source = match
      @source.parse_json_bytes_preserving(@utf8.encode(body), {
        max_input_bytes: 4096,
        max_nodes: 12,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise RemoteCredentialDecodeStop
    }
    let object = credential_decoded(
      @decode.closed_object(
        credential_decoded(
          @decode.admit(source, {
            max_nodes: 12,
            max_depth: 2,
            max_string_bytes: 512,
            max_total_string_bytes: 2048,
          }),
        ),
        ["grant_cid", "use_id", "use_ordinal", "version"],
      ),
    )
    let use_id = credential_text(object, "use_id")
    let ordinal = credential_int(object, "use_ordinal")
    if credential_text(object, "version") != "actql-remote-credential-use/0.1" ||
      credential_text(object, "grant_cid") != grant.identity ||
      !installation_preparation_text(use_id, 256) ||
      ordinal <= 0 ||
      ordinal > grant.max_uses {
      return Err(CredentialUseCollision)
    }
    let pending : InstallationPreparationCredentialUse = {
      grant,
      use_id,
      ordinal,
      identity: "pending",
    }
    let canonical = match installation_preparation_use_body(pending) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let digest = match @sha.text_hex(canonical) {
      Ok(value) => value
      Err(_) => return Err(InvalidCredentialGrant)
    }
    if canonical != body || "sha256:" + digest != expected_cid {
      Err(CredentialUseCollision)
    } else {
      Ok({ ..pending, identity: "sha256:" + digest, })
    }
  } catch {
    RemoteCredentialDecodeStop => Err(InvalidCredentialGrant)
  }
}
