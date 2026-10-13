///|
/// Original metadata custody in the existing installation journal. Only this
/// Host module can construct it; it is not a grant, key body or signing permit.
struct NativeLocalSigningKeyOriginal {
  account : NativeLocalSigningAccountBinding
  projection : @filesystem.PrivateFileProjection
  exported : Bytes
  generation_cid : String
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
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  let (_, purpose, _, _, _, _, _, _) = @credential_resource.native_local_signing_key_selection_projection(
    account.selection,
  )
  local_adoption_record([
    ("adoption_cid", account.host.adoption_cid),
    ("authority_scope_cid", account.scope),
    ("installation_configuration_cid", account.file.content_cid),
    ("projection", @base64.encode(projection)),
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
  let fields = match
    local_adoption_fields(payload, [
      "adoption_cid", "authority_scope_cid", "installation_configuration_cid", "projection",
      "purpose", "version",
    ]) {
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
  if fields[0] != host.adoption_cid ||
    fields[1] != scope ||
    fields[2] != file.content_cid ||
    fields[4] != local_signing_installation_purpose(purpose) ||
    fields[5] != "actql-native-local-installation-original/0.1" {
    return Err(CustodyLost)
  }
  let projection = @base64.decode(fields[3]) catch {
    _ => return Err(CustodyLost)
  }
  if projection.length() <= 106 ||
    projection.length() > 234 ||
    @base64.encode(projection) != fields[3] ||
    projection[106:].to_owned() != @utf8.encode(private_key_file) {
    return Err(CustodyLost)
  }
  Ok(projection)
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
    let other = match
      read_local_installation_projection(self, file, row.body) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
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
        if own_purpose != other_purpose &&
          (same_file || own_public_key == other_public_key) {
          return Err(ChangedIntent)
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
    let exported = local_signing_original_value(
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
              local_signing_installation_value(
                read_local_installation_projection(
                  self.host,
                  self.file,
                  row.body,
                ).map_err(_ => CustodyLost),
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
              let payload = local_signing_installation_value(
                local_signing_installation_payload(self, original).map_err(_ => {
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
              original
            }
            Err(issue) => return Err(Physical(issue))
          }
          local_signing_installation_value(
            self.host.require_distinct_signing_key_locked(self.file, original),
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
    Ok({ account: self, projection, exported, generation_cid, })
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
      restored.generation_cid != self.generation_cid {
      return Err(SigningOriginalUnavailable)
    }
    self.account
    .require_current_account()
    .map_err(issue => SigningAccount(issue))
  } catch {
    LocalSigningOriginalStop(issue) => Err(issue)
  }
}
