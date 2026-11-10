///|
/// Assembly of existing Client custody adapters in one private Local Host.
/// This is a connection, not an independent Run or recovery Owner. Source and
/// Effect work still require the current account's separate authorization.
struct NativeLocalHostConnection {
  session : NativeLocalAdoptionSession
  database : @sqlite.Database
  epoch : NativeClientEpochAuthority
  journal : NativeClientRunJournal
  adoption_body : Bytes
  adoption_cid : String
  ownership : @filesystem.NativeFileOwnership
  mut worker_provisioning_attempt : NativeLocalWorkerProvisioningAttempt?
  mut reviewer_signing_attempt : NativeLocalInitialResolutionSigning?
  mut host_attestation_signing_attempt : NativeLocalInitialHostAttestationSigning?
  mut packaged_runtime : NativeLocalRuntimeBinding?
  mut closed : Bool
  mut database_closed : Bool
  mut session_closed : Bool
}

///|
fn local_journal_body(
  session : NativeLocalAdoptionSession,
  configuration_custody_cid : String,
  ownership : @filesystem.NativeFileOwnership,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  @host.client_local_journal_custody_record(
    session.intent_cid,
    configuration_custody_cid,
    (ownership.device, ownership.inode),
  ).map_err(_ => NativeLocalAdoptionIssue::Encoding)
}

///|
fn NativeLocalAdoptionSession::prepare_journal_file(
  self : NativeLocalAdoptionSession,
  crypto : @crypto.Library,
) -> Result[(@filesystem.NativeFileOwnership, Bytes), NativeLocalAdoptionIssue] {
  match self.stage_configuration() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (configuration_custody, _) = match
    local_adoption_read(self.root, "configuration-custody.json", 8192L) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let configuration_custody_cid = match
    local_adoption_digest(crypto, configuration_custody) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let existing = match self.root.inspect_generation("client.sqlite3") {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let ownership = match existing {
    None if self.existing_only => return Err(CustodyLost)
    None => {
      // Retained proof with a missing DB is custody loss, never first use.
      for name in ["journal-custody.json", "journal-initializing.json"] {
        match self.root.inspect_generation(name) {
          Ok(None) => ()
          Ok(Some(_)) => return Err(CustodyLost)
          Err(issue) => return Err(Filesystem(issue))
        }
      }
      let file = match local_adoption_write(self.root, "client.sqlite3", b"") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let ownership : @filesystem.NativeFileOwnership = {
        device: file.device,
        inode: file.inode,
      }
      let body = match
        local_journal_body(self, configuration_custody_cid, ownership) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match local_adoption_write(self.root, "journal-custody.json", body) {
        Ok(_) => ownership
        Err(issue) => return Err(issue)
      }
    }
    Some(file) => {
      let (body, _) = match
        local_adoption_read(self.root, "journal-custody.json", 8192L) {
        Ok(value) => value
        Err(CustodyLost) => return Err(AmbiguousInitialization)
        Err(issue) => return Err(issue)
      }
      let ownership : @filesystem.NativeFileOwnership = {
        device: file.device,
        inode: file.inode,
      }
      let expected = match
        local_journal_body(self, configuration_custody_cid, ownership) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if body != expected {
        return Err(CustodyLost)
      }
      ownership
    }
  }
  let body = match
    local_journal_body(self, configuration_custody_cid, ownership) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // stage_configuration admitted this source at entry. These trusted custody
  // reads and writes do not introduce another source-admission boundary.
  Ok((ownership, body))
}

///|
/// Finalize a new Host exactly once, or reopen its original adoption. The
/// initializing marker precedes every schema/key write. Missing custody after
/// that point stays unresolved and cannot regenerate keys or permissions.
pub fn NativeLocalAdoptionSession::open_journal(
  self : NativeLocalAdoptionSession,
  library : @sqlite.Library,
  crypto : @crypto.Library,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
) -> Result[NativeLocalHostConnection, NativeLocalAdoptionIssue] {
  self.open_journal_selected(
    library,
    crypto,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
    [],
  )
}

///|
// The optional installer selection is not a caller-provided "first" fact.
// Only the original durable marker/DB inspection below decides capture versus
// restore. The ordinary public wrapper always supplies an empty selection.
fn NativeLocalAdoptionSession::open_journal_selected(
  self : NativeLocalAdoptionSession,
  library : @sqlite.Library,
  crypto : @crypto.Library,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
  signing : Array[NativeLocalSigningInstallationSelection],
  initial_signing? : NativeLocalInitialSigningMaterial? = None,
  initial_policy? : @host.ClientLocalSigningBootstrapPolicy? = None,
) -> Result[NativeLocalHostConnection, NativeLocalAdoptionIssue] {
  if !valid_local_journal_options(ttl_ms, max_records, max_snapshot_bytes) {
    return Err(InvalidInput)
  }
  let (ownership, adoption_body) = match self.prepare_journal_file(crypto) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let first = match self.prepare_journal_marker(ownership, adoption_body) {
    Err(issue) => return Err(issue)
    Ok(true) => true
    // The existing-only SQLite entrance cannot initialize missing schema or
    // keys. Its fixed adoption/epoch anchors are checked before any command.
    // Copying and auditing all historical rows is an explicit recovery task.
    Ok(false) => false
  }
  if !first && (initial_signing is Some(_) || initial_policy is Some(_)) {
    return Err(AmbiguousInitialization)
  }
  let opening = if first {
    library.initialize_owned_database(
      self.state_path + "/client.sqlite3",
      ownership,
      131072L,
    )
  } else {
    library.open_existing_database(self.state_path + "/client.sqlite3", 131072L)
  }
  let database = match opening {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let connected = self.bind_journal(
    database, crypto, ownership, adoption_body, first, ttl_ms, max_records, signing,
    initial_signing, initial_policy,
  )
  match connected {
    Ok(value) => Ok(value)
    // Preserve the same physical handle, original refusal and cleanup duty.
    Err(issue) => Err(DatabasePending(database, issue))
  }
}

///|
fn NativeLocalAdoptionSession::bind_journal(
  self : NativeLocalAdoptionSession,
  database : @sqlite.Database,
  crypto : @crypto.Library,
  ownership : @filesystem.NativeFileOwnership,
  adoption_body : Bytes,
  first : Bool,
  ttl_ms : Double,
  max_records : Int,
  signing : Array[NativeLocalSigningInstallationSelection],
  initial_signing : NativeLocalInitialSigningMaterial?,
  initial_policy : @host.ClientLocalSigningBootstrapPolicy?,
) -> Result[NativeLocalHostConnection, NativeLocalAdoptionIssue] {
  let initial = match (initial_signing, initial_policy) {
    (None, None) => None
    (Some(material), Some(policy)) if first =>
      match
        self.prepare_initial_signing_capture(
          material, policy, crypto, adoption_body,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => Some(value)
      }
    _ => return Err(InvalidInput)
  }
  let (epoch, journal) = match
    self.bind_journal_sqlite_originals(
      database, crypto, adoption_body, first, initial, ttl_ms, max_records,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let adoption_cid = match local_adoption_digest(crypto, adoption_body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The SAME physical adoption row/epoch has now acknowledged persistence.
  // Bind its actual identity to the installed profile, never a fresh record
  // fabricated by the caller or an acknowledgement before COMMIT. The Native
  // Session keeps that exact configuration and custody through current reads.
  if self.configuration.bootstrap_profile() is Some(profile) {
    if @authorization.bind_bootstrap_adoption(self.configuration, {
        record_id: adoption_cid,
        account_id: self.configuration.account_id(),
        profile,
      })
      is Err(_) {
      return Err(UninstalledBootstrapProfile)
    }
  }
  let connected = {
    session: self,
    database,
    epoch,
    journal,
    adoption_body,
    adoption_cid,
    ownership,
    closed: false,
    database_closed: false,
    session_closed: false,
    packaged_runtime: None,
    worker_provisioning_attempt: None,
    reviewer_signing_attempt: None,
    host_attestation_signing_attempt: None,
  }
  match connected.check_binding_sqlite_fence() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match connected.check_database_file_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // The adoption row and epoch anchors were admitted above in this closed
  // opening sequence. Retain the selected settings once on this open; there
  // was no application callback or new source operation in between.
  match self.settings.check_retained(database) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match connected.bootstrap_signing_originals(crypto, signing, first) {
    Ok(_) => Ok(connected)
    Err(issue) => Err(issue)
  }
}

///|
fn local_adoption_row(
  database : @sqlite.Database,
  body : Bytes,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  local_adoption_original_row(database, body, reads~).map(_ => ())
}

///|
// Retain the actual admitted row for a closed opening/read operation instead
// of selecting and comparing that unchanged original again in material binding.
fn local_adoption_original_row(
  database : @sqlite.Database,
  body : Bytes,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[@sqlite.NativeJournalEntry, NativeLocalAdoptionIssue] {
  guard scan_client_journal_value(database, "client_local_adoption", "", reads)
    is Ok(first) &&
    first.key == "adoption" &&
    first.revision == 0L &&
    first.body == body &&
    scan_client_journal_value(
      database, "client_local_adoption", "adoption", reads,
    )
    is Err(@sqlite.NotFound) else {
    return Err(CustodyLost)
  }
  Ok(first)
}

///|
pub fn NativeLocalHostConnection::check_binding(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.check_binding_read_prefix() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.check_binding_sqlite_fence() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.check_binding_read_original() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.check_binding_sqlite_original()
}

///|
/// Returns an admitted configuration, not an allow decision or dispatch permit.
pub fn NativeLocalHostConnection::configuration(
  self : NativeLocalHostConnection,
) -> Result[
  @authorization.AdmittedAccountConfiguration,
  NativeLocalAdoptionIssue,
] {
  self.check_binding().map(_ => self.session.configuration)
}

///|
pub fn NativeLocalHostConnection::epoch_authority(
  self : NativeLocalHostConnection,
) -> Result[NativeClientEpochAuthority, NativeLocalAdoptionIssue] {
  self.check_binding().map(_ => self.epoch)
}

///|
pub fn NativeLocalHostConnection::run_journal(
  self : NativeLocalHostConnection,
) -> Result[NativeClientRunJournal, NativeLocalAdoptionIssue] {
  self.check_binding().map(_ => self.journal)
}

///|
pub fn NativeLocalHostConnection::adoption_cid(
  self : NativeLocalHostConnection,
) -> String {
  self.adoption_cid
}

///|
pub fn NativeLocalHostConnection::close(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  self.closed = true
  match self.close_original_signing_attempts() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.close_journal_database() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.close_journal_session()
}

///|
// The same Host retains both attempts before any fallible signing callback.
// Only their original physical close ACKs cut those aliases, including errors.
fn NativeLocalHostConnection::close_original_signing_attempts(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.reviewer_signing_attempt is Some(original) {
    match original.close_checked() {
      Err(issue) => return Err(Crypto(issue))
      Ok(_) => self.reviewer_signing_attempt = None
    }
  }
  if self.host_attestation_signing_attempt is Some(original) {
    match original.close_checked() {
      Err(issue) => return Err(Crypto(issue))
      Ok(_) => self.host_attestation_signing_attempt = None
    }
  }
  Ok(())
}

///|
fn NativeLocalHostConnection::close_journal_database(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  self.journal.admitted_record = None
  self.journal.admitted_adoption = None
  if !self.database_closed {
    match self.database.close_checked() {
      Ok(_) => self.database_closed = true
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok(())
}

///|
fn NativeLocalHostConnection::close_journal_session(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if !self.session_closed {
    if !self.session.close() {
      return Err(CustodyLost)
    }
    self.session_closed = true
  }
  Ok(())
}

///|
fn valid_local_journal_options(
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
) -> Bool {
  !(!valid_epoch_clock(ttl_ms) ||
  ttl_ms < 1.0 ||
  ttl_ms > 86400000.0 ||
  max_records < 1 ||
  max_snapshot_bytes < 0L ||
  max_snapshot_bytes > 536870912L)
}

///|
// Read/grant history permits at most 64 entries per selected Run. The policy
// product is Int64; the actual stored counter remains the existing Int wire.
fn local_journal_related_issuance_count(
  body : Bytes,
  revision : Int64,
  max_records : Int,
) -> Result[Int, NativeClientRunJournalIssue] {
  if max_records < 1 {
    return Err(CustodyLost)
  }
  let count = match @host.client_journal_issuance_count(body, 2147483647) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if count.to_int64() > max_records.to_int64() * 64L ||
    revision != count.to_int64() {
    return Err(CustodyLost)
  }
  Ok(count)
}

///|
// Refuse an actual exhausted Int counter BEFORE insertion or issued CAS.
// A larger future policy product alone is not a reason to reject the policy.
fn local_journal_related_append_available(
  count : Int,
  max_records : Int,
) -> Bool {
  max_records > 0 &&
  count >= 0 &&
  count < 2147483647 &&
  count.to_int64() < max_records.to_int64() * 64L
}
