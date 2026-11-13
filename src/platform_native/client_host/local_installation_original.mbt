///|
priv suberror LocalInstallationAdoptionStop {
  LocalInstallationAdoptionStop(NativeLocalAdoptionIssue)
}

///|
priv suberror LocalInstallationJournalStop {
  LocalInstallationJournalStop(NativeClientRunJournalIssue)
}

///|
priv suberror LocalInstallationPreparationStop {
  LocalInstallationPreparationStop(NativeLocalSalesforcePreparationIssue)
}

///|
// These are additions to the existing private Host journal and its bounded
// settings capacity. Missing witnesses never authorize installation bootstrap.
fn initialize_local_installation_originals(
  database : @sqlite.Database,
  adoption : Bytes,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match check_empty_local_installation_originals(database, bootstrap~) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  insert_local_installation_control(database, adoption, bootstrap~)
}

///|
fn check_empty_local_installation_originals(
  database : @sqlite.Database,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  for
    table in [
      "client_local_installation_custody", "client_local_installation_originals",
    ] {
    match
      scan_client_journal_value(
        database,
        table,
        "",
        bootstrap_journal_reads(bootstrap),
      ) {
      Err(@sqlite.NotFound) => ()
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
  }
  match
    bootstrap_journal_capacity_usage(
      database, "client_local_settings", bootstrap,
    ) {
    Ok(value) if value.reserved_bytes == 0L && value.reserved_objects == 0L =>
      ()
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  Ok(())
}

///|
fn insert_local_installation_control(
  database : @sqlite.Database,
  body : Bytes,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match
    insert_bootstrap_journal_value(
      database, "client_local_installation_custody", "host", body, bootstrap,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  insert_bootstrap_journal_value(
    database, "client_local_installation_custody", "issued", b"0", bootstrap,
  )
  .map(_ => ())
  .map_err(issue => NativeLocalAdoptionIssue::Physical(issue))
}

///|
priv struct NativeLocalPreparationInstallationSelection {
  credential_file : String
  provider_file : String
}

///|
// Only an initially selected setting names the original private-root file.
// No secret bytes, future claim, Site or Dispatch are configuration material.
fn local_preparation_installation_selection(
  body : Bytes,
) -> Result[
  NativeLocalPreparationInstallationSelection,
  NativeLocalAdoptionIssue,
] {
  try {
    let cursor = local_issuer_decoded(
      @decode.admit(
        @source.parse_json_bytes_preserving(body, {
          max_input_bytes: 8192,
          max_nodes: 16,
          max_depth: 4,
        })
        .map_err(_ => LocalCredentialIssuerStop(InvalidOriginal))
        .unwrap_or_error(),
        {
          max_nodes: 16,
          max_depth: 4,
          max_string_bytes: 128,
          max_total_string_bytes: 512,
        },
      ),
    )
    let root = local_issuer_decoded(
      @decode.closed_object(cursor, ["version", "native"]),
    )
    if local_issuer_text(root, "version", 32) != "actql-config/0.1" {
      return Err(InvalidInput)
    }
    let native = local_issuer_decoded(
      @decode.closed_object(local_issuer_field(root, "native"), [
        "preparation_credential",
      ]),
    )
    let fields = local_issuer_decoded(
      @decode.closed_object(
        local_issuer_field(native, "preparation_credential"),
        ["credential_file", "provider_file"],
      ),
    )
    let selected = {
      credential_file: local_issuer_text(fields, "credential_file", 128),
      provider_file: local_issuer_text(fields, "provider_file", 128),
    }
    if !local_adoption_name(selected.credential_file) ||
      !local_adoption_name(selected.provider_file) ||
      selected.credential_file == selected.provider_file {
      return Err(InvalidInput)
    }
    Ok(selected)
  } catch {
    LocalCredentialIssuerStop(_) => Err(InvalidInput)
  }
}

///|
fn local_installation_payload(
  host : NativeLocalHostConnection,
  file : NativeLocalSelectedFile,
  provider : NativeLocalSelectedFile,
  projection : Bytes,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  local_adoption_record([
    ("adoption_cid", host.adoption_cid),
    ("installation_configuration_cid", file.content_cid),
    ("provider_configuration_cid", provider.content_cid),
    ("projection", @base64.encode(projection)),
    ("version", "actql-native-local-installation-original/0.1"),
  ])
}

///|
// Reuse the existing private epoch key and crypto implementation with a
// distinct closed preimage. Never generate another key to repair custody.
fn local_installation_packet(
  host : NativeLocalHostConnection,
  payload : Bytes,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  local_installation_packet_in_transaction(
    host.database,
    host.epoch.crypto,
    payload,
  )
}

///|
fn local_installation_packet_in_transaction(
  database : @sqlite.Database,
  crypto : @crypto.Library,
  payload : Bytes,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  // The initializer and established Host use the same original epoch key and
  // exact packet encoding. Existing callers and their refusal order are intact.
  try {
    let (key, _, _) = read_epoch_custody(database, reads~)
      .map_err(issue => NativeLocalAdoptionIssue::Epoch(issue))
      .map_err(issue => LocalInstallationAdoptionStop(issue))
      .unwrap_or_error()
    let tag = crypto
      .hmac_sha256(key, payload)
      .map_err(issue => NativeLocalAdoptionIssue::Crypto(issue))
      .map_err(issue => LocalInstallationAdoptionStop(issue))
      .unwrap_or_error()
    local_adoption_record([
      ("payload", @base64.encode(payload)),
      ("tag", epoch_hex(tag)),
    ])
  } catch {
    LocalInstallationAdoptionStop(issue) => Err(issue)
  }
}

///|
fn read_local_installation_authenticated_payload(
  host : NativeLocalHostConnection,
  packet : Bytes,
  signing_original? : NativeLocalInitialSigningOriginal? = None,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  let (payload, tag) = match local_installation_packet_data(packet) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match
    authenticate_local_installation_payload(
      host,
      payload,
      tag,
      signing_original~,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(payload)
  }
}

///|
// Canonical packet DATA only. Retaining these private bytes never retains an
// authentication result; every consumer below must run the actual current MAC.
fn local_installation_packet_data(
  packet : Bytes,
) -> Result[(Bytes, Bytes), NativeLocalAdoptionIssue] {
  try {
    let envelope = local_adoption_fields(packet, ["payload", "tag"])
      .map_err(issue => LocalInstallationAdoptionStop(issue))
      .unwrap_or_error()
    let payload = @base64.decode(envelope[0]) catch {
      _ => return Err(CustodyLost)
    }
    guard payload.length() <= 2048 &&
      @base64.encode(payload) == envelope[0] &&
      epoch_hex_bytes(envelope[1]) is Some(tag) else {
      return Err(CustodyLost)
    }
    Ok((payload, tag))
  } catch {
    LocalInstallationAdoptionStop(issue) => Err(issue)
  }
}

///|
// Shared actual authentication, not a permit or cached successful comparison.
// The independent reader supplies freshly decoded packet DATA; the entered
// original may supply only its own private, byte-identical admitted control.
fn authenticate_local_installation_payload(
  host : NativeLocalHostConnection,
  payload : Bytes,
  tag : Bytes,
  signing_original? : NativeLocalInitialSigningOriginal? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if payload.length() > 2048 || tag.length() != 32 {
    return Err(CustodyLost)
  }
  try {
    let valid = match signing_original {
      None => {
        let (key, _, _) = read_epoch_custody(host.database)
          .map_err(issue => NativeLocalAdoptionIssue::Epoch(issue))
          .map_err(issue => LocalInstallationAdoptionStop(issue))
          .unwrap_or_error()
        host.epoch.crypto
        .verify_hmac_sha256(key, payload, tag)
        .map_err(issue => NativeLocalAdoptionIssue::Crypto(issue))
      }
      Some(original) => {
        original
        .check_initial_control_read_scope(host)
        .map_err(issue => LocalInstallationAdoptionStop(issue))
        .unwrap_or_error()
        host.epoch
        .verify_control_payload_in_operation(payload, tag)
        .map_err(issue => {
          match issue {
            NativeClientEpochIssue::Crypto(original) =>
              NativeLocalAdoptionIssue::Crypto(original)
            _ => NativeLocalAdoptionIssue::Epoch(issue)
          }
        })
      }
    }
    guard valid
      .map_err(issue => LocalInstallationAdoptionStop(issue))
      .unwrap_or_error() else {
      return Err(CustodyLost)
    }
    Ok(())
  } catch {
    LocalInstallationAdoptionStop(issue) => Err(issue)
  }
}

///|
fn read_local_installation_projection(
  host : NativeLocalHostConnection,
  file : NativeLocalSelectedFile,
  packet : Bytes,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  try {
    let payload = read_local_installation_authenticated_payload(host, packet)
      .map_err(issue => LocalInstallationAdoptionStop(issue))
      .unwrap_or_error()
    // The exact adopted configuration selects one closed role. No other file
    // is searched and an unknown role never repairs a retained original.
    if local_preparation_installation_selection(file.body) is Err(_) {
      return read_local_signing_installation_projection(host, file, payload)
    }
    let fields = local_adoption_fields(payload, [
        "adoption_cid", "installation_configuration_cid", "provider_configuration_cid",
        "projection", "version",
      ])
      .map_err(issue => LocalInstallationAdoptionStop(issue))
      .unwrap_or_error()
    let selection = local_preparation_installation_selection(file.body)
      .map_err(issue => LocalInstallationAdoptionStop(issue))
      .unwrap_or_error()
    guard host.session.settings.files
      .iter()
      .find_first(value => value.name == selection.provider_file)
      is Some(provider) &&
      fields[0] == host.adoption_cid &&
      fields[1] == file.content_cid &&
      fields[2] == provider.content_cid &&
      fields[4] == "actql-native-local-installation-original/0.1" else {
      return Err(CustodyLost)
    }
    let original = @base64.decode(fields[3]) catch {
      _ => return Err(CustodyLost)
    }
    if original.length() <= 106 ||
      original.length() > 234 ||
      @base64.encode(original) != fields[3] ||
      original[106:].to_owned() != @utf8.encode(selection.credential_file) {
      return Err(CustodyLost)
    }
    Ok(original)
  } catch {
    LocalInstallationAdoptionStop(issue) => Err(issue)
  }
}

///|
fn NativeLocalHostConnection::installation_custody(
  self : NativeLocalHostConnection,
) -> Result[(Int, Int64), NativeLocalAdoptionIssue] {
  try {
    guard self.database.scan_after("client_local_installation_custody", "")
      is Ok(host) &&
      host.key == "host" &&
      host.revision == 0L &&
      valid_local_installation_control(self, host.body) &&
      self.database.scan_after("client_local_installation_custody", "host")
      is Ok(witness) &&
      witness.key == "issued" &&
      self.database.scan_after("client_local_installation_custody", "issued")
      is Err(@sqlite.NotFound) else {
      return Err(CustodyLost)
    }
    let text = @utf8.decode(witness.body) catch { _ => return Err(CustodyLost) }
    if text.is_empty() || text.length() > 1 {
      return Err(CustodyLost)
    }
    let count = @string.parse_int(text) catch { _ => return Err(CustodyLost) }
    if count < 0 ||
      count > 8 ||
      count > self.session.settings.files.length() + 1 ||
      count.to_string() != text ||
      witness.revision != count.to_int64() {
      return Err(CustodyLost)
    }
    let mut cursor = ""
    for _ in 0..<count {
      let row = self.database
        .scan_after("client_local_installation_originals", cursor)
        .map_err(issue => NativeLocalAdoptionIssue::Physical(issue))
        .map_err(issue => LocalInstallationAdoptionStop(issue))
        .unwrap_or_error()
      guard row.revision == 0L else { return Err(CustodyLost) }
      // A new reservation during lookup is custody loss; the enclosing journal
      // transaction rolls back instead of repairing the original budget.
      guard self.database
        .reserve_capacity_in_transaction(
          "client_local_settings",
          "installation:" + row.key,
          8192L,
          1L,
          65536L,
          8L,
        )
        .map_err(issue => NativeLocalAdoptionIssue::Physical(issue))
        .map_err(issue => LocalInstallationAdoptionStop(issue))
        .unwrap_or_error() ==
        false else {
        return Err(CustodyLost)
      }
      if row.key == local_policy_upgrade_key {
        read_local_policy_upgrade_original(self, {
          body: row.body,
          revision: row.revision,
        })
        .map_err(_ => LocalInstallationAdoptionStop(CustodyLost))
        .unwrap_or_error()
        |> ignore
      } else {
        guard self.session.settings.files
          .iter()
          .find_first(file => file.name == row.key)
          is Some(file) else {
          return Err(CustodyLost)
        }
        read_local_installation_projection(self, file, row.body)
        .map_err(issue => LocalInstallationAdoptionStop(issue))
        .unwrap_or_error()
        |> ignore
      }
      cursor = row.key
    }
    guard self.database.scan_after(
        "client_local_installation_originals", cursor,
      )
      is Err(@sqlite.NotFound) else {
      return Err(CustodyLost)
    }
    guard self.database.capacity_usage("client_local_settings") is Ok(usage) &&
      usage.reserved_objects == count.to_int64() &&
      usage.reserved_bytes == count.to_int64() * 8192L else {
      return Err(CustodyLost)
    }
    Ok((count, witness.revision))
  } catch {
    LocalInstallationAdoptionStop(issue) => Err(issue)
  }
}

///|
// Installation persistence and lookup collect the same current facts under
// the existing journal lock. No Bool or public CID substitutes for live Work.
fn NativeLocalSalesforcePreparationBinding::installation_current_locked(
  self : NativeLocalSalesforcePreparationBinding,
  target : NativeClientLocalPreparationTarget,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let before = self.host.journal.publication_read_locked
  self.host.journal.publication_read_locked = true
  let result = self.require_target(target)
  self.host.journal.publication_read_locked = before
  result.map_err(_ => AuthorizationDenied)
}

///|
// The storage transaction is shared by append and restore. Only the public
// binding supplies its original opaque Work/read check; custody alone is not
// operational authorization and never issues a grant or enters HTTP.
fn NativeLocalHostConnection::installation_original_locked(
  self : NativeLocalHostConnection,
  file : NativeLocalSelectedFile,
  provider : NativeLocalSelectedFile,
  selection : NativeLocalPreparationInstallationSelection,
  adopt : Bool,
  current : () -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[@filesystem.PrivateFileProjection, NativeClientRunJournalIssue] {
  try {
    current()
    .map_err(issue => LocalInstallationJournalStop(issue))
    .unwrap_or_error()
    let (count, revision) = self
      .installation_custody()
      .map_err(_ => NativeClientRunJournalIssue::CustodyLost)
      .map_err(issue => LocalInstallationJournalStop(issue))
      .unwrap_or_error()
    let row = self.database.read(
      "client_local_installation_originals",
      file.name,
    )
    let original = match row {
      Ok(row) => {
        if row.revision != 0L {
          return Err(CustodyLost)
        }
        let bytes = read_local_installation_projection(self, file, row.body)
          .map_err(_ => NativeClientRunJournalIssue::CustodyLost)
          .map_err(issue => LocalInstallationJournalStop(issue))
          .unwrap_or_error()
        self
        .require_distinct_signing_key_locked(file, bytes)
        .map_err(issue => LocalInstallationJournalStop(issue))
        .unwrap_or_error()
        self.session.source_root
        .restore_private_file_projection(bytes)
        .map_err(_ => NativeClientRunJournalIssue::CustodyLost)
        .map_err(issue => LocalInstallationJournalStop(issue))
        .unwrap_or_error()
      }
      Err(@sqlite.NotFound) => {
        if !adopt || count >= 8 {
          return Err(CustodyLost)
        }
        // Reserve before exporting/copying descriptor material. This uses the
        // existing settings capacity and unchanged physical journal limit.
        guard self.database
          .reserve_capacity_in_transaction(
            "client_local_settings",
            "installation:" + file.name,
            8192L,
            1L,
            65536L,
            8L,
          )
          .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
          .map_err(issue => LocalInstallationJournalStop(issue))
          .unwrap_or_error() else {
          return Err(CustodyLost)
        }
        let original = self.session.source_root
          .adopt_private_file_projection(selection.credential_file)
          .map_err(_ => NativeClientRunJournalIssue::CustodyLost)
          .map_err(issue => LocalInstallationJournalStop(issue))
          .unwrap_or_error()
        let exported = original
          .export_original()
          .map_err(_ => NativeClientRunJournalIssue::CustodyLost)
          .map_err(issue => LocalInstallationJournalStop(issue))
          .unwrap_or_error()
        self
        .require_distinct_signing_key_locked(file, exported)
        .map_err(issue => LocalInstallationJournalStop(issue))
        .unwrap_or_error()
        let payload = local_installation_payload(self, file, provider, exported)
          .map_err(_ => NativeClientRunJournalIssue::Encoding)
          .map_err(issue => LocalInstallationJournalStop(issue))
          .unwrap_or_error()
        let packet = local_installation_packet(self, payload)
          .map_err(_ => NativeClientRunJournalIssue::CustodyLost)
          .map_err(issue => LocalInstallationJournalStop(issue))
          .unwrap_or_error()
        current()
        .map_err(issue => LocalInstallationJournalStop(issue))
        .unwrap_or_error()
        self.database
        .insert("client_local_installation_originals", file.name, packet)
        .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
        .map_err(issue => LocalInstallationJournalStop(issue))
        .unwrap_or_error()
        |> ignore
        self.database
        .compare_exchange(
          "client_local_installation_custody",
          "issued",
          revision,
          @utf8.encode((count + 1).to_string()),
        )
        .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
        .map_err(issue => LocalInstallationJournalStop(issue))
        .unwrap_or_error()
        |> ignore
        original
      }
      Err(issue) => return Err(Physical(issue))
    }
    current()
    .map_err(issue => LocalInstallationJournalStop(issue))
    .unwrap_or_error()
    Ok(original)
  } catch {
    LocalInstallationJournalStop(issue) => Err(issue)
  }
}

///|
fn NativeLocalSalesforcePreparationBinding::original_installation(
  self : NativeLocalSalesforcePreparationBinding,
  target : NativeClientLocalPreparationTarget,
  setting_name : String,
  adopt : Bool,
) -> Result[
  @credential_resource.NativeLocalPreparationCredentialInstallation,
  NativeLocalSalesforcePreparationIssue,
] {
  try {
    self
    .require_target(target)
    .map_err(issue => LocalInstallationPreparationStop(issue))
    .unwrap_or_error()
    guard self.host.session.settings.files
      .iter()
      .find_first(file => file.name == setting_name)
      is Some(file) else {
      return Err(ForeignInstallation)
    }
    let selection = local_preparation_installation_selection(file.body)
      .map_err(issue => NativeLocalSalesforcePreparationIssue::Adoption(issue))
      .map_err(issue => LocalInstallationPreparationStop(issue))
      .unwrap_or_error()
    if selection.provider_file != self.file.name ||
      self.host.session.settings.files.any(value => {
        value.name == selection.credential_file
      }) ||
      selection.credential_file == self.host.session.source_name {
      return Err(ForeignInstallation)
    }
    let projection = self.host.journal
      .transaction(() => {
        self.host.installation_original_locked(
          file,
          self.file,
          selection,
          adopt,
          () => self.installation_current_locked(target),
        )
      })
      .map_err(issue => NativeLocalSalesforcePreparationIssue::Journal(issue))
      .map_err(issue => LocalInstallationPreparationStop(issue))
      .unwrap_or_error()
    // Commit/ACK loss never creates a replacement original. A final current
    // check precedes returning the opaque file to existing transport assembly.
    self
    .require_target(target)
    .map_err(issue => LocalInstallationPreparationStop(issue))
    .unwrap_or_error()
    Ok({
      operation: {
        resource_origin: self.selection.resource_origin,
        operation: "salesforce:record:observe",
        path: @catalog.local_target_read_request_path(target.request),
        // The real original basename is metadata only; the Local hook exclusively
        // opens the opaque file. Remote/Resume secret path semantics are unchanged.
        secret_path: selection.credential_file,
        verb: @http.Get,
        max_request_bytes: 0,
      },
      file: projection,
    })
  } catch {
    LocalInstallationPreparationStop(issue) => Err(issue)
  }
}

///|
/// Explicitly persist one original selected installation before acknowledging
/// it. Repetition reuses authenticated bytes; it does not issue or use a grant.
pub fn NativeLocalSalesforcePreparationBinding::adopt_credential_installation(
  self : NativeLocalSalesforcePreparationBinding,
  target : NativeClientLocalPreparationTarget,
  installation_setting : String,
) -> Result[
  @credential_resource.NativeLocalPreparationCredentialInstallation,
  NativeLocalSalesforcePreparationIssue,
] {
  self.original_installation(target, installation_setting, true)
}

///|
/// Restore only authenticated original custody under current Work/read policy.
/// Missing/changed material is refusal; no stat-based adoption or send occurs.
pub fn NativeLocalSalesforcePreparationBinding::restore_credential_installation(
  self : NativeLocalSalesforcePreparationBinding,
  target : NativeClientLocalPreparationTarget,
  installation_setting : String,
) -> Result[
  @credential_resource.NativeLocalPreparationCredentialInstallation,
  NativeLocalSalesforcePreparationIssue,
] {
  self.original_installation(target, installation_setting, false)
}
