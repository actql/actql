///|
// Private original metadata in the same grant transaction and capacity bucket.
// The production supplier is the checked live operation, never a URL, fresh
// Catalog or caller string. The grant packet and public identity stay unchanged.
priv struct NativeLocalPreparationOriginalTarget {
  resource : String
  provider_file_name : String
  provider_selection_cid : String
}

///|
fn NativeLocalPreparationGrantOperation::original_target_material(
  self : NativeLocalPreparationGrantOperation,
) -> Result[
  NativeLocalPreparationOriginalTarget,
  NativeLocalSalesforcePreparationIssue,
] {
  self
  .require_current()
  .map(_ => {
    resource: self.provider.resource,
    provider_file_name: self.provider.file.name,
    provider_selection_cid: self.provider.file.content_cid,
  })
}

///|
// Borrow existing checked strings until the original bucket is reserved.
// The payload is bounded before authentication; the envelope retains the
// existing setting codec bound and uses the original private epoch key.
fn local_preparation_target_payload(
  original : NativeLocalGrantOriginal,
  target : NativeLocalPreparationOriginalTarget,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  guard original.grant is PreparationGrant(grant) else {
    return Err(ForeignRun)
  }
  let scope = @credential.local_preparation_credential_grant_scope(grant)
  if target.resource.is_empty() ||
    target.resource.length() > 4096 ||
    target.resource.contains("\u{0}") ||
    target.provider_file_name.is_empty() ||
    target.provider_file_name.length() > 256 ||
    target.provider_file_name.contains("\u{0}") ||
    target.provider_selection_cid.length() != 71 ||
    !target.provider_selection_cid.has_prefix("sha256:") {
    return Err(ChangedIntent)
  }
  let fields = [
    ("domain", "actql-native-local-preparation-target-original/0.1"),
    ("operation_cid", original.operation_cid),
    ("grant_cid", @credential.local_preparation_credential_grant_cid(grant)),
    ("request_scope_cid", @host.client_request_scope_cid(original.request)),
    ("host_adoption_cid", scope.host_adoption_cid),
    ("run_invocation_cid", scope.run_invocation_cid),
    ("operation_occurrence_cid", scope.operation_occurrence_cid),
    ("issuer_selection_cid", original.issuer_selection_cid),
    ("provider_file_name", target.provider_file_name),
    ("provider_selection_cid", target.provider_selection_cid),
    ("resource", target.resource),
  ]
  let writer = @encode.writer(3072, 64, 4) catch { _ => return Err(Encoding) }
  try {
    @encode.begin_object(writer)
    for field in fields {
      @encode.key(writer, field.0)
      @encode.string_value(writer, field.1)
    }
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(CapacityExceeded)
  }
}

///|
fn local_preparation_target_record(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
  target : NativeLocalPreparationOriginalTarget,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  let payload = match local_preparation_target_payload(original, target) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (key, _, _) = match read_epoch_custody(host.database) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(issue))
  }
  let tag = match host.epoch.crypto.hmac_sha256(key, payload) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(Crypto(issue)))
  }
  local_adoption_record([
    ("payload", @base64.encode(payload)),
    ("tag", epoch_hex(tag)),
  ]).map_err(_ => CapacityExceeded)
}

///|
fn read_local_preparation_target_record(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
  row : @sqlite.NativeJournalEntry,
) -> Result[NativeLocalPreparationOriginalTarget, NativeClientRunJournalIssue] {
  if row.revision != 0L {
    return Err(CustodyLost)
  }
  let envelope = match local_adoption_fields(row.body, ["payload", "tag"]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let payload = @base64.decode(envelope[0]) catch {
    _ => return Err(CustodyLost)
  }
  guard payload.length() <= 3072 &&
    @base64.encode(payload) == envelope[0] &&
    epoch_hex_bytes(envelope[1]) is Some(tag) else {
    return Err(CustodyLost)
  }
  let (key, _, _) = match read_epoch_custody(host.database) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(issue))
  }
  match host.epoch.crypto.verify_hmac_sha256(key, payload, tag) {
    Ok(true) => ()
    Ok(false) => return Err(CustodyLost)
    Err(issue) => return Err(Epoch(Crypto(issue)))
  }
  let fields = match
    local_adoption_fields(payload, [
      "domain", "operation_cid", "grant_cid", "request_scope_cid", "host_adoption_cid",
      "run_invocation_cid", "operation_occurrence_cid", "issuer_selection_cid", "provider_file_name",
      "provider_selection_cid", "resource",
    ]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let target : NativeLocalPreparationOriginalTarget = {
    resource: fields[10],
    provider_file_name: fields[8],
    provider_selection_cid: fields[9],
  }
  guard local_preparation_target_payload(original, target) is Ok(exact) &&
    exact == payload else {
    return Err(CustodyLost)
  }
  Ok(target)
}

///|
// Caller holds the original Host journal transaction and its current read
// authorization. Missing legacy target material remains unavailable; this
// cannot backfill a target from current configuration or mint another grant.
fn NativeLocalHostConnection::lookup_preparation_target_original_locked(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  original : NativeLocalGrantOriginal,
) -> Result[NativeLocalPreparationOriginalTarget?, NativeClientRunJournalIssue] {
  match self.lookup_local_grant_original_locked(crypto, original) {
    Ok(Some(_)) => ()
    Ok(None) => return Ok(None)
    Err(issue) => return Err(issue)
  }
  let key = match
    local_grant_original_key(crypto, original.request, original.operation_id) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.database.read("client_local_preparation_target_originals", key) {
    Ok(row) =>
      read_local_preparation_target_record(self, original, {
        key,
        body: row.body,
        revision: row.revision,
      }).map(value => Some(value))
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
// This comparison reuses authenticated original metadata. It obtains no
// replacement target, grant, HTTP client, secret or issuer issue permission.
fn NativeLocalPreparationGrantOperation::require_original_target_locked(
  self : NativeLocalPreparationGrantOperation,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let target = match
    self.provider.host.lookup_preparation_target_original_locked(
      self.provider.crypto,
      self.original,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  if target.resource != self.provider.resource ||
    target.provider_file_name != self.provider.file.name ||
    target.provider_selection_cid != self.provider.file.content_cid {
    return Err(ChangedIntent)
  }
  self.require_current_locked()
}
