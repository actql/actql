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
  match self.check_original() {
    Ok(_) => Ok((ownership, body))
    Err(issue) => Err(issue)
  }
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
  if !valid_epoch_clock(ttl_ms) ||
    ttl_ms < 1.0 ||
    ttl_ms > 86400000.0 ||
    max_records < 1 ||
    max_records > 1024 ||
    max_snapshot_bytes < 0L ||
    max_snapshot_bytes > 536870912L {
    return Err(InvalidInput)
  }
  let (ownership, adoption_body) = match self.prepare_journal_file(crypto) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let marker = match self.root.inspect_generation("journal-initializing.json") {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let first = match marker {
    None if self.existing_only => return Err(CustodyLost)
    None => {
      guard self.root.inspect_generation("client.sqlite3") is Ok(Some(file)) &&
        file.device == ownership.device &&
        file.inode == ownership.inode &&
        file.size == 0L else {
        return Err(CustodyLost)
      }
      match
        local_adoption_write(
          self.root,
          "journal-initializing.json",
          adoption_body,
        ) {
        Ok(_) => true
        Err(issue) => return Err(issue)
      }
    }
    Some(_) => {
      let (body, _) = match
        local_adoption_read(self.root, "journal-initializing.json", 8192L) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if body != adoption_body {
        return Err(CustodyLost)
      }
      // The original commit may have succeeded. Inspect, never rerun bootstrap.
      match
        inspect_native_client_state(
          library,
          self.state_path + "/client.sqlite3",
          131072L,
          max_snapshot_bytes,
          max_records,
        ) {
        Ok(Retained) => false
        Ok(PhysicallyAbsent) => return Err(CustodyLost)
        Err(issue) => return Err(Inspection(issue))
      }
    }
  }
  match self.check_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
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
    database, crypto, ownership, adoption_body, first, ttl_ms, max_records,
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
) -> Result[NativeLocalHostConnection, NativeLocalAdoptionIssue] {
  match self.check_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if first {
    match
      initialize_native_local_client_custody(
        database,
        crypto,
        adoption_body,
        settings=Some(self.settings),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  match local_adoption_row(database, adoption_body) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let epoch = match
    open_native_client_epoch_authority(database, crypto, ttl_ms) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(issue))
  }
  let journal = match open_native_client_run_journal(database, max_records) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  match journal.submitted_intent_custody() {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  match self.check_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let adoption_cid = match local_adoption_digest(crypto, adoption_body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
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
  }
  match connected.check_binding() {
    Ok(_) => Ok(connected)
    Err(issue) => Err(issue)
  }
}

///|
fn local_adoption_row(
  database : @sqlite.Database,
  body : Bytes,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard database.scan_after("client_local_adoption", "") is Ok(first) &&
    first.key == "adoption" &&
    first.revision == 0L &&
    first.body == body &&
    database.scan_after("client_local_adoption", "adoption")
    is Err(@sqlite.NotFound) else {
    return Err(CustodyLost)
  }
  Ok(())
}

///|
pub fn NativeLocalHostConnection::check_binding(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.packaged_runtime is Some(binding) &&
    binding.current.check_current() is Err(_) {
    return Err(CustodyLost)
  }
  if self.database.transaction_fenced() {
    return Err(Fenced)
  }
  match self.session.check_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.session.stage_configuration() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard self.session.root.inspect_generation("client.sqlite3") is Ok(Some(file)) &&
    file.device == self.ownership.device &&
    file.inode == self.ownership.inode else {
    return Err(CustodyLost)
  }
  match self.session.settings.check_retained(self.database) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  local_adoption_row(self.database, self.adoption_body)
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
  if !self.database_closed {
    match self.database.close_checked() {
      Ok(_) => self.database_closed = true
      Err(issue) => return Err(Physical(issue))
    }
  }
  if !self.session_closed {
    if !self.session.close() {
      return Err(CustodyLost)
    }
    self.session_closed = true
  }
  Ok(())
}
