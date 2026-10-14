///|
fn catalog_use_matches_dispatch(
  request : @remote.DispatchRequest,
  grant : @credential.RemoteCredentialGrant,
  credential_use : @credential.RemoteCredentialUse,
) -> Bool {
  let fields = @credential.credential_grant_projection(grant)
  let execution = @remote.dispatch_request_execution_scope(request)
  let route = @remote.dispatch_request_journal_key(request)
  let use_fields = @credential.credential_use_projection(credential_use)
  fields.length() == 17 &&
  execution.length() >= 3 &&
  route.length() == 7 &&
  use_fields.length() == 4 &&
  use_fields[1] == fields[0] &&
  fields[5] == execution[0] &&
  fields[6] == execution[1] &&
  fields[7] == execution[2] &&
  fields[11] == "salesforce:catalog:describe" &&
  fields[13] == route[6] &&
  fields[14] == @remote.dispatch_request_identity(request)
}

///|
/// Inspect the original use retained before Provider I/O, independently of the
/// credential database. Missing custody remains NotFound, never a fresh-read
/// permit. Current Host/grant authorization and original invocation admission
/// are separate requirements; this read issues no send or completion evidence.
pub fn Journal::effect_catalog_use(
  self : Journal,
  request : @remote.DispatchRequest,
  original_grant : @credential.RemoteCredentialGrant,
  original_use_id : String,
) -> Result[@credential.RemoteCredentialUse, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  match self.require(request) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let saved = match
    self.database.read(
      "site_effect_catalog_use",
      @remote.dispatch_request_identity(request),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  if saved.revision != 0L ||
    saved.body.length().to_int64() > self.max_record_bytes {
    return Err(StateCollision)
  }
  let body = @utf8.decode(saved.body) catch { _ => return Err(StateCollision) }
  guard body.find("\n") is Some(separator) else { return Err(StateCollision) }
  let cid = body[:separator].to_owned()
  let wire = body[separator + 1:].to_owned()
  let original = match
    @credential.admit_credential_use_json(original_grant, wire, cid) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  if !catalog_use_matches_dispatch(request, original_grant, original) ||
    @credential.credential_use_projection(original)[2] != original_use_id {
    return Err(StateCollision)
  }
  Ok(original)
}

///|
/// The credential Resource Owner calls this after recording its nominal use
/// and before its final authorization fence/Provider send. One immutable use
/// occupies the original consumer dispatch slot. Commit/readback failure grants
/// no I/O permission; a retry retains exactly the same use. This witness does
/// not prove delivery, credential-DB continuity, or Catalog/cleanup success.
pub fn Journal::retain_effect_catalog_use(
  self : Journal,
  request : @remote.DispatchRequest,
  original_grant : @credential.RemoteCredentialGrant,
  credential_use : @credential.RemoteCredentialUse,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  if !catalog_use_matches_dispatch(request, original_grant, credential_use) {
    return Err(StateCollision)
  }
  let cid = @credential.credential_use_cid(credential_use)
  let wire = match @credential.credential_use_json(credential_use) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  // Re-admit against the selected original grant, rather than assuming that a
  // nominal use supplied by a different grant shares this custody context.
  match @credential.admit_credential_use_json(original_grant, wire, cid) {
    Ok(_) => ()
    Err(_) => return Err(StateCollision)
  }
  let bytes = @utf8.encode(cid + "\n" + wire)
  if bytes.length().to_int64() > self.max_record_bytes {
    return Err(Physical(@sqlite.CapacityExceeded))
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = (fn() {
    let record = match self.require(request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let key = @remote.dispatch_request_identity(request)
    match self.database.read("site_effect_catalog_use", key) {
      Ok(saved) if saved.revision == 0L && saved.body == bytes => Ok(())
      Ok(_) => Err(StateCollision)
      Err(@sqlite.NotFound) => {
        match self.cancellation_requested(request) {
          Ok(false) => ()
          Ok(true) => return Err(StateCollision)
          Err(issue) => return Err(issue)
        }
        guard @remote.dispatch_record_state(record)
          is (@remote.NativeSettled, _, @remote.CleanupActive, _, _) else {
          return Err(StateCollision)
        }
        self.database
        .insert("site_effect_catalog_use", key, bytes)
        .map(_ => ())
        .map_err(issue => Physical(issue))
      }
      Err(issue) => Err(Physical(issue))
    }
  })()
  match self.finish_effect_checkpoint_mutation(result) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self
  .effect_catalog_use(
    request,
    original_grant,
    @credential.credential_use_projection(credential_use)[2],
  )
  .map(_ => ())
}
