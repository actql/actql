///|
// Authenticated signature DATA in this same Host's existing immutable record
// protocol. It is not a grant, Host attestation, Resolution or return permit.
fn local_initial_resolution_signature_fields(
  original : NativeLocalGrantOriginal,
  signing_use : @credential.LocalSigningCredentialUse,
  signature : String,
  candidate_cid? : String? = None,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  guard original.grant is SigningGrant(grant) else { return Err(CustodyLost) }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  if signature.length() != 88 ||
    @credential.local_signing_credential_use_projection(signing_use).0 !=
    @credential.local_signing_credential_grant_cid(grant) {
    return Err(CustodyLost)
  }
  let bytes = @base64.decode(signature[:]) catch { _ => return Err(Encoding) }
  if bytes.length() != 64 || @base64.encode(bytes) != signature {
    return Err(Encoding)
  }
  let fields = [
    ("grant_cid", @credential.local_signing_credential_grant_cid(grant)),
    ("key_public_key_cid", scope.key_public_key_cid),
    ("operation_cid", original.operation_cid),
    ("preimage", scope.preimage),
    ("signature", signature),
    ("use_cid", @credential.local_signing_credential_use_cid(signing_use)),
    ("version", "actql-native-local-installation-original/0.1"),
  ]
  if candidate_cid is Some(cid) {
    fields.push(("candidate_cid", cid))
  }
  local_adoption_record(fields).map_err(_ => Encoding)
}

///|
fn local_initial_resolution_signature_locked(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
  signing_use : @credential.LocalSigningCredentialUse,
) -> Result[String, NativeClientRunJournalIssue] {
  local_initial_resolution_result_locked(host, original, signing_use).map(value => {
    value.0
  })
}

///|
// The optional candidate is authenticated by the same small signature packet.
// A legacy signature-only row stays metadata and cannot acquire a missing wire.
fn local_initial_resolution_result_locked(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
  signing_use : @credential.LocalSigningCredentialUse,
) -> Result[(String, String?), NativeClientRunJournalIssue] {
  if !host.journal.transaction_active || host.journal.fenced {
    return Err(Fenced)
  }
  let row = match
    host.database.read(
      "client_local_signing_result_originals",
      original.operation_cid,
    ) {
    Err(issue) => return Err(Physical(issue))
    Ok(value) if value.revision == 0L => value
    Ok(_) => return Err(CustodyLost)
  }
  let payload = match
    read_local_installation_authenticated_payload(host, row.body) {
    Err(_) => return Err(CustodyLost)
    Ok(value) => value
  }
  let keys = [
    "grant_cid", "key_public_key_cid", "operation_cid", "preimage", "signature",
    "use_cid", "version",
  ]
  let extended = keys.copy()
  extended.push("candidate_cid")
  let fields = match local_adoption_fields(payload, extended) {
    Ok(value) => value
    Err(_) =>
      match local_adoption_fields(payload, keys) {
        Err(_) => return Err(CustodyLost)
        Ok(value) => value
      }
  }
  let candidate_cid = if fields.length() == 8 { Some(fields[7]) } else { None }
  let expected = match
    local_initial_resolution_signature_fields(
      original,
      signing_use,
      fields[4],
      candidate_cid~,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if payload != expected {
    return Err(CustodyLost)
  }
  let candidate = match candidate_cid {
    None => None
    Some(cid) => {
      let saved = match
        host.database.read(
          "client_local_signing_candidate_originals",
          original.operation_cid,
        ) {
        Ok(value) if value.revision == 0L &&
          value.body.length() <= native_checkpoint_limits().max_wire_bytes =>
          value.body
        _ => return Err(CustodyLost)
      }
      if !(local_adoption_digest(host.epoch.crypto, saved) is Ok(actual) &&
        actual == cid) {
        return Err(CustodyLost)
      }
      let wire = @utf8.decode(saved) catch { _ => return Err(CustodyLost) }
      Some(wire)
    }
  }
  Ok((fields[4], candidate))
}

///|
// The caller has already confirmed its original claim, retained the physical
// result and checked current subject/authority. This same TX joins signature
// custody and terminal metadata. It never creates or repairs an old signature.
fn store_local_initial_resolution_signature_locked(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
  signing_use : @credential.LocalSigningCredentialUse,
  signature : String,
  prepared? : @checkpoint.PreparedResolutionProof? = None,
  approval? : @checkpoint.PreparedEffectApprovalProof? = None,
  attested? : @checkpoint.AdmittedResolution? = None,
  attested_limits? : @checkpoint.WireLimits = native_checkpoint_limits(),
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !host.journal.transaction_active || host.journal.fenced {
    return Err(Fenced)
  }
  guard original.grant is SigningGrant(grant) else { return Err(CustodyLost) }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let candidate = match prepared {
    None => None
    Some(proof) => {
      if proof.preimage() != scope.preimage ||
        proof.checkpoint().checkpoint_cid != scope.checkpoint_cid {
        return Err(ChangedIntent)
      }
      let wire = match
        @checkpoint.seal_prepared_resolution_proof(
          proof,
          scope.key_id,
          signature,
        ) {
        Ok(value) => value
        Err(_) => return Err(Encoding)
      }
      let bytes = @utf8.encode(wire)
      if bytes.length() > native_checkpoint_limits().max_wire_bytes {
        return Err(CapacityExceeded)
      }
      Some(bytes)
    }
  }
  let candidate = match approval {
    None => candidate
    Some(proof) => {
      if prepared is Some(_) ||
        attested is Some(_) ||
        proof.preimage() != scope.preimage ||
        proof.checkpoint().checkpoint_cid != scope.checkpoint_cid ||
        scope.purpose != @credential.ReviewerProof {
        return Err(ChangedIntent)
      }
      let wire = match
        @checkpoint.seal_prepared_effect_approval_proof(
          proof,
          scope.key_id,
          signature,
        ) {
        Ok((wire, _)) => wire
        Err(_) => return Err(Encoding)
      }
      let bytes = @utf8.encode(wire)
      if bytes.length() > native_checkpoint_limits().max_wire_bytes {
        return Err(CapacityExceeded)
      }
      Some(bytes)
    }
  }
  let candidate = match attested {
    None => candidate
    Some(admitted) => {
      if prepared is Some(_) ||
        approval is Some(_) ||
        original.initial_issue is None ||
        scope.purpose != @credential.HostAttestation ||
        scope.preimage != admitted.attestation_preimage ||
        scope.checkpoint_cid != admitted.checkpoint_cid {
        return Err(ChangedIntent)
      }
      let original_body = match
        local_initial_host_prepared_locked(host, original) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if admitted.prepared_wire(attested_limits) !=
        Ok(@utf8.decode(original_body) catch { _ => return Err(CustodyLost) }) {
        return Err(ChangedIntent)
      }
      let verified = match
        @checkpoint.seal_verified_resolution(
          admitted,
          scope.key_id,
          signature,
          attested_limits,
        ) {
        Ok(value) => value
        Err(_) => return Err(Encoding)
      }
      Some(@utf8.encode(verified.wire))
    }
  }
  let candidate_cid = match candidate {
    None => None
    Some(bytes) =>
      match local_adoption_digest(host.epoch.crypto, bytes) {
        Ok(cid) => Some(cid)
        Err(_) => return Err(CustodyLost)
      }
  }
  let payload = match
    local_initial_resolution_signature_fields(
      original,
      signing_use,
      signature,
      candidate_cid~,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) if value.length() <= 2048 => value
    Ok(_) => return Err(CapacityExceeded)
  }
  let packet = match
    local_installation_packet_in_transaction(
      host.database,
      host.epoch.crypto,
      payload,
    ) {
    Err(_) => return Err(CustodyLost)
    Ok(value) => value
  }
  // The wire and its small authenticated packet spend the same existing
  // per-Run grant bucket. No new reservation, quota or physical holding is made.
  let (_, _, runs) = match host.local_grant_custody(host.epoch.crypto) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let reservation = local_original_grant_reservation_scope(original)
  guard runs.get(reservation) is Some((_, used)) else {
    return Err(CustodyLost)
  }
  if packet.length() + candidate.map(bytes => bytes.length()).unwrap_or(0) >
    65536 - used {
    return Err(CapacityExceeded)
  }
  if candidate is Some(bytes) {
    match
      host.database.insert(
        "client_local_signing_candidate_originals",
        original.operation_cid,
        bytes,
      ) {
      Ok(0L) => ()
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
  }
  match
    host.database.insert(
      "client_local_signing_result_originals",
      original.operation_cid,
      packet,
    ) {
    Ok(0L) => ()
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  let outcome = if scope.purpose == @credential.HostAttestation {
    @credential_resource.record_native_local_initial_host_signing_outcome_in_transaction(
      host.database,
      grant,
      signing_use,
      @credential_resource.Succeeded,
    )
  } else {
    @credential_resource.record_native_local_original_signing_outcome_in_transaction(
      host.database,
      grant,
      signing_use,
      @credential_resource.Succeeded,
    )
  }
  match outcome {
    Err(_) => return Err(CustodyLost)
    Ok(_) => ()
  }
  match local_initial_resolution_signature_locked(host, original, signing_use) {
    Ok(value) if value == signature => Ok(())
    Ok(_) => Err(CustodyLost)
    Err(issue) => Err(issue)
  }
}
