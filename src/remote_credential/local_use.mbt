///|
fn local_credential_use_body(
  value : LocalCredentialUse,
) -> Result[String, RemoteCredentialIssue] {
  credential_use_record_body(
    value.grant.grant_cid,
    value.use_id,
    value.use_ordinal,
    "actql-local-credential-use/0.1",
  )
}

///|
fn local_credential_use_identity(
  value : LocalCredentialUse,
) -> Result[String, RemoteCredentialIssue] {
  let body = match local_credential_use_body(value) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @sha.text_hex(body)
  .map(value => "sha256:" + value)
  .map_err(_ => InvalidCredentialGrant)
}

///|
/// The physical credential Owner claims the ordinal durably before I/O. This
/// typed check binds the use to its original Local scope; it is not a claim,
/// an approval or a replacement for current Host/cancellation fencing.
pub fn prepare_local_credential_use(
  grant : LocalCredentialGrant,
  use_id : String,
  trusted_now_ms : Int64,
  used_count : Int,
  revoked : Bool,
  current_scope : LocalCredentialScope,
) -> Result[LocalCredentialUse, RemoteCredentialIssue] {
  if local_credential_grant_json(grant) is Err(_) ||
    !bounded_text(use_id, 256) ||
    trusted_now_ms < 0L ||
    trusted_now_ms >= grant.expires_unix_ms ||
    used_count < 0 ||
    used_count >= grant.max_uses ||
    revoked ||
    current_scope != grant.scope {
    return Err(CredentialGrantInactive)
  }
  let pending : LocalCredentialUse = {
    grant,
    use_id,
    use_ordinal: used_count + 1,
    use_cid: "pending",
  }
  local_credential_use_identity(pending).map(cid => { ..pending, use_cid: cid, })
}

///|
pub fn local_credential_use_json(
  value : LocalCredentialUse,
) -> Result[String, RemoteCredentialIssue] {
  let identity = match local_credential_use_identity(value) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if identity != value.use_cid {
    return Err(CredentialUseCollision)
  }
  local_credential_use_body(value)
}

///|
pub fn local_credential_use_cid(value : LocalCredentialUse) -> String {
  value.use_cid
}

///|
pub fn local_credential_use_projection(
  value : LocalCredentialUse,
) -> (String, String, Int) {
  (value.grant.grant_cid, value.use_id, value.use_ordinal)
}

///|
pub fn authorize_local_credential_use(
  value : LocalCredentialUse,
  trusted_now_ms : Int64,
  revoked : Bool,
  current_scope : LocalCredentialScope,
) -> Result[Unit, RemoteCredentialIssue] {
  if local_credential_grant_json(value.grant) is Err(_) ||
    local_credential_use_json(value) is Err(_) ||
    trusted_now_ms < 0L ||
    trusted_now_ms >= value.grant.expires_unix_ms ||
    value.use_ordinal < 1 ||
    value.use_ordinal > value.grant.max_uses ||
    revoked ||
    current_scope != value.grant.scope {
    Err(CredentialGrantInactive)
  } else {
    Ok(())
  }
}

///|
/// Restore only the exact originally claimed Local use, without claiming an
/// ordinal, refreshing its expiry, or interpreting unknown sends as unsent.
pub fn admit_local_credential_use_json(
  grant : LocalCredentialGrant,
  body : String,
  claimed_use_cid : String,
) -> Result[LocalCredentialUse, RemoteCredentialIssue] {
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
    let cursor = credential_decoded(
      @decode.admit(source, {
        max_nodes: 12,
        max_depth: 2,
        max_string_bytes: 4096,
        max_total_string_bytes: 4096,
      }),
    )
    let object = credential_decoded(
      @decode.closed_object(cursor, [
        "grant_cid", "use_id", "use_ordinal", "version",
      ]),
    )
    if local_credential_grant_json(grant) is Err(_) ||
      credential_text(object, "version") != "actql-local-credential-use/0.1" ||
      credential_text(object, "grant_cid") != grant.grant_cid {
      return Err(CredentialUseCollision)
    }
    let use_id = credential_text(object, "use_id")
    let ordinal = credential_int(object, "use_ordinal")
    if !bounded_text(use_id, 256) || ordinal < 1 || ordinal > grant.max_uses {
      return Err(CredentialUseCollision)
    }
    let pending : LocalCredentialUse = {
      grant,
      use_id,
      use_ordinal: ordinal,
      use_cid: "pending",
    }
    let identity = match local_credential_use_identity(pending) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let restored = { ..pending, use_cid: identity, }
    if identity != claimed_use_cid ||
      local_credential_use_json(restored) != Ok(body) {
      Err(CredentialUseCollision)
    } else {
      Ok(restored)
    }
  } catch {
    RemoteCredentialDecodeStop => Err(InvalidCredentialGrant)
  }
}
