///|
// Typed alternatives of the same grant custody Owner. No variant's
// public identity constitutes an operational Work/resume token.
priv enum NativeLocalOriginalGrant {
  ResumeGrant(@credential.LocalCredentialGrant)
  PreparationGrant(@credential.LocalPreparationCredentialGrant)
  SigningGrant(@credential.LocalSigningCredentialGrant)
}

///|
priv struct NativeLocalOriginalGrantFacts {
  account_configuration_cid : String
  account_id : String
  authority_scope_cid : String
  host_adoption_cid : String
  principal : String
  submission_scope_cid : String
}

///|
fn local_original_grant_facts(
  grant : NativeLocalOriginalGrant,
) -> NativeLocalOriginalGrantFacts {
  match grant {
    ResumeGrant(value) => {
      let scope = @credential.local_credential_grant_scope(value)
      {
        account_configuration_cid: scope.account_configuration_cid,
        account_id: scope.account_id,
        authority_scope_cid: scope.authority_scope_cid,
        host_adoption_cid: scope.host_adoption_cid,
        principal: scope.principal,
        submission_scope_cid: scope.submission_scope_cid,
      }
    }
    PreparationGrant(value) => {
      let scope = @credential.local_preparation_credential_grant_scope(value)
      {
        account_configuration_cid: scope.account_configuration_cid,
        account_id: scope.account_id,
        authority_scope_cid: scope.authority_scope_cid,
        host_adoption_cid: scope.host_adoption_cid,
        principal: scope.principal,
        submission_scope_cid: scope.submission_scope_cid,
      }
    }
    SigningGrant(value) => {
      let scope = @credential.local_signing_credential_grant_scope(value)
      {
        account_configuration_cid: scope.account_configuration_cid,
        account_id: scope.account_id,
        authority_scope_cid: scope.authority_scope_cid,
        host_adoption_cid: scope.host_adoption_cid,
        principal: scope.principal,
        submission_scope_cid: scope.submission_scope_cid,
      }
    }
  }
}

///|
fn local_original_grant_cid(grant : NativeLocalOriginalGrant) -> String {
  match grant {
    ResumeGrant(value) => @credential.local_credential_grant_cid(value)
    PreparationGrant(value) =>
      @credential.local_preparation_credential_grant_cid(value)
    SigningGrant(value) => @credential.local_signing_credential_grant_cid(value)
  }
}

///|
fn local_original_grant_json(
  grant : NativeLocalOriginalGrant,
) -> Result[String, @credential.RemoteCredentialIssue] {
  match grant {
    ResumeGrant(value) => @credential.local_credential_grant_json(value)
    PreparationGrant(value) =>
      @credential.local_preparation_credential_grant_json(value)
    SigningGrant(value) =>
      @credential.local_signing_credential_grant_json(value)
  }
}

///|
fn local_original_grant_limits(
  grant : NativeLocalOriginalGrant,
) -> (Int, Int64) {
  match grant {
    ResumeGrant(value) => @credential.local_credential_grant_limits(value)
    PreparationGrant(value) =>
      @credential.local_preparation_credential_grant_limits(value)
    SigningGrant(value) =>
      @credential.local_signing_credential_grant_limits(value)
  }
}

///|
fn local_original_grant_matches_issuer(
  grant : NativeLocalOriginalGrant,
  selection : NativeLocalCredentialIssuerSelection,
) -> Bool {
  let expires = @values.timestamp_epoch_milliseconds(selection.expires_at)
  guard expires is Some(expiry) else { return false }
  let expected = match grant {
    ResumeGrant(value) =>
      @credential.prepare_local_credential_grant(
        selection.issuer_authority,
        @credential.local_credential_grant_scope(value),
        expiry,
        selection.max_uses,
      ).map(value => @credential.local_credential_grant_cid(value))
    PreparationGrant(value) =>
      @credential.prepare_local_preparation_credential_grant(
        selection.issuer_authority,
        @credential.local_preparation_credential_grant_scope(value),
        expiry,
        selection.max_uses,
      ).map(value => @credential.local_preparation_credential_grant_cid(value))
    SigningGrant(value) =>
      @credential.prepare_local_signing_credential_grant(
        selection.issuer_authority,
        @credential.local_signing_credential_grant_scope(value),
        expiry,
        selection.max_uses,
      ).map(value => @credential.local_signing_credential_grant_cid(value))
  }
  expected == Ok(local_original_grant_cid(grant))
}

///|
fn local_grant_packet_object(
  body : Bytes,
) -> Result[@decode.ObjectView, NativeClientRunJournalIssue] {
  // Parse only to select the closed variant, then reuse the same finite
  // custody decoder for the full exact field set. Invalid/null originals do
  // not fall back to another variant or acquire a replacement fence.
  let source = match
    @source.parse_json_bytes_preserving(body, {
      max_input_bytes: 49152,
      max_nodes: 8,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 8,
      max_depth: 2,
      max_string_bytes: 49152,
      max_total_string_bytes: 49152,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let object = match @decode.open_object(cursor) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let names = match
    (
      @decode.lookup(object, "preparation_fence"),
      @decode.lookup(object, "signing_purpose"),
    ) {
    (None, None) => ["grant", "intent"]
    (Some(_), None) => ["grant", "intent", "preparation_fence"]
    (None, Some(_)) => ["grant", "intent", "signing_purpose"]
    (Some(_), Some(_)) => return Err(CustodyLost)
  }
  local_read_evidence_object(body, names, 49152)
}

///|
fn local_original_grant_from_packet(
  crypto : @crypto.Library,
  packet : @decode.ObjectView,
  wire : String,
  cid : String,
) -> Result[NativeLocalOriginalGrant, NativeClientRunJournalIssue] {
  if @decode.lookup(packet, "signing_purpose") is Some(_) {
    guard epoch_text(packet, "signing_purpose") is Some(purpose) else {
      return Err(CustodyLost)
    }
    let grant = match
      @credential.admit_local_signing_credential_grant_json(wire, cid) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    if purpose !=
      local_signing_installation_purpose(
        @credential.local_signing_credential_grant_scope(grant).purpose,
      ) {
      return Err(CustodyLost)
    }
    return Ok(SigningGrant(grant))
  }
  match @decode.lookup(packet, "preparation_fence") {
    None =>
      @credential.admit_local_credential_grant_json(wire, cid)
      .map(value => ResumeGrant(value))
      .map_err(_ => CustodyLost)
    _ => {
      guard epoch_text(packet, "preparation_fence") is Some(body) else {
        return Err(CustodyLost)
      }
      // The actual full original body determines its CID; grant admission
      // separately verifies that exact CID and its original scope projections.
      let fence_cid = match local_adoption_digest(crypto, @utf8.encode(body)) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let fence = match
        @credential.admit_local_preparation_fence_json(body, fence_cid) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      @credential.admit_local_preparation_credential_grant_json(
        wire, cid, fence,
      )
      .map(value => PreparationGrant(value))
      .map_err(_ => CustodyLost)
    }
  }
}
