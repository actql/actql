///|
/// Original metadata custody in the existing installation journal. Only this
/// Host module can construct it; it is not a grant, key body or signing permit.
struct NativeLocalSigningKeyOriginal {
  account : NativeLocalSigningAccountBinding
  projection : @filesystem.PrivateFileProjection
  exported : Bytes
  generation_cid : String
  public_key : @credential.LocalSigningPublicKey
}

///|
priv suberror LocalSigningOriginalStop {
  LocalSigningOriginalStop(NativeLocalSigningOriginalIssue)
}

///|
fn[T] local_signing_original_value(
  value : Result[T, NativeLocalSigningOriginalIssue],
) -> T raise LocalSigningOriginalStop {
  match value {
    Ok(value) => value
    Err(issue) => raise LocalSigningOriginalStop(issue)
  }
}

///|
fn[T] local_signing_installation_value(
  value : Result[T, NativeClientRunJournalIssue],
) -> T raise LocalInstallationJournalStop {
  match value {
    Ok(value) => value
    Err(issue) => raise LocalInstallationJournalStop(issue)
  }
}

///|
pub(all) enum NativeLocalSigningOriginalIssue {
  SigningAccount(NativeLocalSigningAccountIssue)
  SigningOriginalUnavailable
  SigningCustody(NativeLocalAdoptionIssue)
  SigningJournal(NativeClientRunJournalIssue)
}

///|
fn local_signing_installation_purpose(
  purpose : @credential.LocalSigningPurpose,
) -> String {
  match purpose {
    @credential.ReviewerProof => "reviewer_proof"
    @credential.HostAttestation => "host_attestation"
  }
}

///|
// Closed alternative in the same private installation domain. Old preparation
// and policy-upgrade payloads retain their original fields and exact bytes.
fn local_signing_installation_payload(
  account : NativeLocalSigningAccountBinding,
  projection : Bytes,
  public_key : @credential.LocalSigningPublicKey,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  let (_, purpose, _, _, _, _, _, _) = @credential_resource.native_local_signing_key_selection_projection(
    account.selection,
  )
  local_adoption_record([
    ("adoption_cid", account.host.adoption_cid),
    ("authority_scope_cid", account.scope),
    ("installation_configuration_cid", account.file.content_cid),
    ("projection", @base64.encode(projection)),
    ("public_key_cid", public_key.cid()),
    ("public_key_original", public_key.json()),
    ("purpose", local_signing_installation_purpose(purpose)),
    ("version", "actql-native-local-installation-original/0.1"),
  ])
}

///|
// HMAC is already verified by the enclosing installation reader. Custody
// validation does not ask for an Allow or construct a signing operation.
fn read_local_signing_installation_projection(
  host : NativeLocalHostConnection,
  file : NativeLocalSelectedFile,
  payload : Bytes,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  read_local_signing_installation_record(host, file, payload).map(record => record.0)
}

///|
fn read_local_signing_installation_record(
  host : NativeLocalHostConnection,
  file : NativeLocalSelectedFile,
  payload : Bytes,
) -> Result[(Bytes, @credential.LocalSigningPublicKey?), NativeLocalAdoptionIssue] {
  let fields = match local_signing_installation_fields(payload) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let wire = @utf8.decode(file.body) catch { _ => return Err(CustodyLost) }
  let selection = match
    @credential_resource.admit_native_local_signing_key_selection(wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let (_, purpose, principal, connection, _, _, private_key_file, _) = @credential_resource.native_local_signing_key_selection_projection(
    selection,
  )
  let scope = match
    host.authority_scope_cid(principal, connection, host.epoch.crypto) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if fields.adoption != host.adoption_cid ||
    fields.scope != scope ||
    fields.configuration != file.content_cid ||
    fields.purpose != local_signing_installation_purpose(purpose) ||
    fields.version != "actql-native-local-installation-original/0.1" {
    return Err(CustodyLost)
  }
  let projection = @base64.decode(fields.projection) catch {
    _ => return Err(CustodyLost)
  }
  if projection.length() <= 106 ||
    projection.length() > 234 ||
    @base64.encode(projection) != fields.projection ||
    projection[106:].to_owned() != @utf8.encode(private_key_file) {
    return Err(CustodyLost)
  }
  Ok((projection, fields.public_key))
}

///|
// A selected original key cannot serve both signing purposes, or be borrowed
// from a preparation credential installation. This checks authenticated rows;
// filenames/CIDs by themselves do not supply permission or key custody.
fn NativeLocalHostConnection::require_distinct_signing_key_locked(
  self : NativeLocalHostConnection,
  own_file : NativeLocalSelectedFile,
  original : Bytes,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let own_wire = @utf8.decode(own_file.body) catch {
    _ => return Err(CustodyLost)
  }
  let own_signing = @credential_resource.admit_native_local_signing_key_selection(
    own_wire,
  )
  if own_signing is Err(_) &&
    local_preparation_installation_selection(own_file.body) is Err(_) {
    return Err(CustodyLost)
  }
  let mut cursor = ""
  for _ in 0..<8 {
    let row = match
      self.database.scan_after("client_local_installation_originals", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => return Ok(())
      Err(issue) => return Err(Physical(issue))
    }
    cursor = row.key
    if row.key == own_file.name || row.key == local_policy_upgrade_key {
      continue
    }
    guard self.session.settings.files
      .iter()
      .find_first(file => file.name == row.key)
      is Some(file) else {
      return Err(CustodyLost)
    }
    let other = match read_local_installation_projection(self, file, row.body) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    // An authenticated row is not proof that its original physical generation
    // still exists. Missing or replaced peer custody cannot prove key separation.
    if self.session.source_root.restore_private_file_projection(other) is Err(_) {
      return Err(CustodyLost)
    }
    // Offsets refer to the closed AQLPFP01 private export protocol, not a
    // native C struct. The existing FileProjection Owner defines these four
    // original root/file dev/inode fields; HMAC authenticates their custody.
    let same_file = other.length() > 106 &&
      other[10:42].to_owned() == original[10:42].to_owned()
    let wire = @utf8.decode(file.body) catch { _ => return Err(CustodyLost) }
    let other_signing = @credential_resource.admit_native_local_signing_key_selection(
      wire,
    )
    match (own_signing, other_signing) {
      (Ok(own), Ok(other)) => {
        let (_, own_purpose, _, _, _, _, _, own_public_key) = @credential_resource.native_local_signing_key_selection_projection(
          own,
        )
        let (_, other_purpose, _, _, _, _, _, other_public_key) = @credential_resource.native_local_signing_key_selection_projection(
          other,
        )
        if own_purpose != other_purpose {
          if same_file {
            return Err(ChangedIntent)
          }
          // Both public originals use the same Host-selected Library. Raw32
          // is comparison material only, never the issuer's public-key CID.
          let own_raw = match
            self.epoch.crypto.ed25519_public_key_raw32(own_public_key) {
            Ok(value) => value
            Err(_) => return Err(CustodyLost)
          }
          let other_raw = match
            self.epoch.crypto.ed25519_public_key_raw32(other_public_key) {
            Ok(value) => value
            Err(_) => return Err(CustodyLost)
          }
          if own_raw == other_raw {
            return Err(ChangedIntent)
          }
        }
      }
      (Ok(_), Err(_)) | (Err(_), Ok(_)) =>
        if same_file {
          return Err(ChangedIntent)
        }
      (Err(_), Err(_)) => ()
    }
  }
  match
    self.database.scan_after("client_local_installation_originals", cursor) {
    Err(@sqlite.NotFound) => Ok(())
    Err(issue) => Err(Physical(issue))
    Ok(_) => Err(CustodyLost)
  }
}

///|
// This private first-capture seam is for the trusted explicit installer only.
// Restore and ordinary use never select it after missing/unknown history.
fn NativeLocalSigningAccountBinding::capture_signing_key_original(
  self : NativeLocalSigningAccountBinding,
) -> Result[NativeLocalSigningKeyOriginal, NativeLocalSigningOriginalIssue] {
  self.signing_key_original(true)
}

///|
/// Restore only the original authenticated row and physical generation. No
/// replacement stat, file discovery, key read, claim or signature occurs.
pub fn NativeLocalSigningAccountBinding::restore_signing_key_original(
  self : NativeLocalSigningAccountBinding,
) -> Result[NativeLocalSigningKeyOriginal, NativeLocalSigningOriginalIssue] {
  self.signing_key_original(false)
}

///|
fn NativeLocalSigningAccountBinding::signing_key_original(
  self : NativeLocalSigningAccountBinding,
  capture : Bool,
) -> Result[NativeLocalSigningKeyOriginal, NativeLocalSigningOriginalIssue] {
  try {
    local_signing_original_value(
      self.require_current_account().map_err(issue => SigningAccount(issue)),
    )
    let (_, _, principal, connection, _, _, private_key_file, _) = @credential_resource.native_local_signing_key_selection_projection(
      self.selection,
    )
    guard self.host.authority_scope_cid(
        principal,
        connection,
        self.host.epoch.crypto,
      )
      is Ok(scope) &&
      scope == self.scope else {
      return Err(SigningOriginalUnavailable)
    }
    let (exported, public_key) = local_signing_original_value(
      self.host.journal
      .transaction(() => {
        try {
          local_signing_installation_value(
            self.require_current_account().map_err(_ => AuthorizationDenied),
          )
          let (count, revision) = local_signing_installation_value(
            self.host.installation_custody().map_err(_ => CustodyLost),
          )
          let original = match
            self.host.database.read(
              "client_local_installation_originals",
              self.file.name,
            ) {
            Ok(row) => {
              if row.revision != 0L {
                return Err(CustodyLost)
              }
              let payload = local_signing_installation_value(
                read_local_installation_authenticated_payload(self.host, row.body)
                .map_err(_ => CustodyLost),
              )
              local_signing_installation_value(
                read_local_signing_installation_record(self.host, self.file, payload)
                .map_err(_ => CustodyLost),
              )
            }
            Err(@sqlite.NotFound) => {
              if !capture || count >= 8 {
                return Err(CustodyLost)
              }
              // Same existing settings reservation, before projection export/copy.
              if !local_signing_installation_value(
                  self.host.database
                  .reserve_capacity_in_transaction(
                    "client_local_settings",
                    "installation:" + self.file.name,
                    8192L,
                    1L,
                    65536L,
                    8L,
                  )
                  .map_err(issue => Physical(issue)),
                ) {
                return Err(CustodyLost)
              }
              let projection = local_signing_installation_value(
                self.host.session.source_root
                .adopt_private_file_projection(private_key_file)
                .map_err(_ => CustodyLost),
              )
              let original = local_signing_installation_value(
                projection.export_original().map_err(_ => CustodyLost),
              )
              local_signing_installation_value(
                self.host.require_distinct_signing_key_locked(
                  self.file,
                  original,
                ),
              )
              let public_key = local_signing_installation_value(
                self.prepare_public_key_original(),
              )
              let payload = local_signing_installation_value(
                local_signing_installation_payload(self, original, public_key).map_err(_ => {
                  Encoding
                }),
              )
              let packet = local_signing_installation_value(
                local_installation_packet(self.host, payload).map_err(_ => {
                  Encoding
                }),
              )
              local_signing_installation_value(
                self.require_current_account().map_err(_ => AuthorizationDenied),
              )
              local_signing_installation_value(
                self.host.database
                .insert(
                  "client_local_installation_originals",
                  self.file.name,
                  packet,
                )
                .map_err(issue => Physical(issue)),
              )
              |> ignore
              local_signing_installation_value(
                self.host.database
                .compare_exchange(
                  "client_local_installation_custody",
                  "issued",
                  revision,
                  @utf8.encode((count + 1).to_string()),
                )
                .map_err(issue => Physical(issue)),
              )
              |> ignore
              (original, Some(public_key))
            }
            Err(issue) => return Err(Physical(issue))
          }
          let (projection, _) = original
          local_signing_installation_value(
            self.host.require_distinct_signing_key_locked(self.file, projection),
          )
          local_signing_installation_value(
            self.require_current_account().map_err(_ => AuthorizationDenied),
          )
          Ok(original)
        } catch {
          LocalInstallationJournalStop(issue) => Err(issue)
        }
      })
      .map_err(issue => SigningJournal(issue)),
    )
    local_signing_original_value(
      self.require_current_account().map_err(issue => SigningAccount(issue)),
    )
    // A legacy authenticated projection remains valid historical custody, but
    // lacks this operational public identity. Never backfill or recapture it.
    guard public_key is Some(public_key) else {
      return Err(SigningOriginalUnavailable)
    }
    let projection = local_signing_original_value(
      self.host.session.source_root
      .restore_private_file_projection(exported)
      .map_err(_ => SigningOriginalUnavailable),
    )
    let generation_cid = local_signing_original_value(
      local_adoption_digest(self.host.epoch.crypto, exported).map_err(issue => {
        SigningCustody(issue)
      }),
    )
    local_signing_original_value(
      self.require_current_account().map_err(issue => SigningAccount(issue)),
    )
    Ok({ account: self, projection, exported, generation_cid, public_key, })
  } catch {
    LocalSigningOriginalStop(issue) => Err(issue)
  }
}

///|
/// Original generation identity, not a grant or permission obtained by copying
/// it. The private original remains attached to the existing Host/Root custody.
pub fn NativeLocalSigningKeyOriginal::generation_cid(
  self : NativeLocalSigningKeyOriginal,
) -> String {
  self.generation_cid
}

///|
/// Authenticated public-byte identity only. Before an operational use, the
/// existing key/crypto Owner must still prove actual private-key correspondence.
/// Copied identity is not a key handle, issuer or purpose/current permission.
pub fn NativeLocalSigningKeyOriginal::public_key_cid(
  self : NativeLocalSigningKeyOriginal,
) -> String {
  self.public_key.cid()
}

///|
/// Actual current Account and original Root/file are rechecked each time. A
/// caller must also bind the original Checkpoint/request/Run/preimage before use.
pub fn NativeLocalSigningKeyOriginal::require_current_key(
  self : NativeLocalSigningKeyOriginal,
) -> Result[Unit, NativeLocalSigningOriginalIssue] {
  try {
    local_signing_original_value(
      self.account
      .require_current_account()
      .map_err(issue => SigningAccount(issue)),
    )
    let live = local_signing_original_value(
      self.projection.export_original().map_err(_ => SigningOriginalUnavailable),
    )
    if live != self.exported {
      return Err(SigningOriginalUnavailable)
    }
    let restored = local_signing_original_value(
      self.account.restore_signing_key_original(),
    )
    if restored.exported != self.exported ||
      restored.generation_cid != self.generation_cid ||
      restored.public_key.json() != self.public_key.json() ||
      restored.public_key.cid() != self.public_key.cid() {
      return Err(SigningOriginalUnavailable)
    }
    self.account
    .require_current_account()
    .map_err(issue => SigningAccount(issue))
  } catch {
    LocalSigningOriginalStop(issue) => Err(issue)
  }
}
