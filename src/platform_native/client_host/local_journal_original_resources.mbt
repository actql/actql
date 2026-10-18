///|
// Retained originals inside the existing Journal capture, not another resource
// Owner. Only an actual successful enter sets leave_pending; only its original
// physical leave clears it. An interruption never supplies a cleanup ACK.
struct NativeLocalJournalOriginalResources {
  host : @arena.InstalledArenaHost
  pair : @arena.InstalledArenaLocalHostResources
  read : @arena.InstalledArenaOriginalRead
  mut leave_pending : Bool
}

///|
/// Prepare the existing Journal capture using an already claimed same-Host
/// pair. Retain the capture before open. This constructor performs no I/O,
/// claim, Library selection, current admission or numerical capacity issue.
/// The original Session must have been acquired inside this original Read.
pub fn prepare_native_local_journal_capture_with_original_resources(
  session : NativeLocalAdoptionSession,
  host : @arena.InstalledArenaHost,
  pair : @arena.InstalledArenaLocalHostResources,
  read : @arena.InstalledArenaOriginalRead,
  crypto : @crypto.Library,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
) -> NativeLocalJournalCapture {
  {
    session,
    library: None,
    original_resources: Some({ host, pair, read, leave_pending: false, }),
    opening_database: None,
    crypto,
    ttl_ms,
    max_records,
    max_snapshot_bytes,
    opening: JournalNotAttempted,
    closing: false,
    cleanup_acknowledged: false,
  }
}

///|
fn[T] NativeLocalJournalOriginalResources::stage(
  self : NativeLocalJournalOriginalResources,
  phase : @arena.InstalledArenaLocalHostPhase,
  operation : () -> Result[T, NativeLocalAdoptionIssue],
  cleanup? : Bool = false,
) -> Result[T, NativeLocalAdoptionIssue] {
  if self.leave_pending {
    return Err(OriginalResourceScopePending)
  }
  if !cleanup {
    match
      self.host.require_local_host_consuming_read_current(self.pair, self.read) {
      Err(issue) => return Err(OriginalResources(issue))
      Ok(_) => ()
    }
  }
  let entered = if cleanup {
    self.host.enter_local_host_cleanup(self.pair, phase)
  } else {
    self.host.enter_local_host_phase(self.pair, phase)
  }
  match entered {
    Err(issue) => return Err(OriginalResources(issue))
    Ok(_) => self.leave_pending = true
  }
  let result = operation()
  match self.host.leave_local_host_phase(self.pair) {
    Ok(_) => {
      self.leave_pending = false
      result
    }
    Err(issue) => {
      let primary = match result {
        Err(original) => Some(original)
        Ok(_) => None
      }
      Err(OriginalResourceLeave(primary, issue))
    }
  }
}

///|
// Cleanup retries only this original pending leave, never the protected stage.
fn NativeLocalJournalOriginalResources::finish_pending_leave(
  self : NativeLocalJournalOriginalResources,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.leave_pending {
    match self.host.leave_local_host_phase(self.pair) {
      Err(issue) => return Err(OriginalResources(issue))
      Ok(_) => self.leave_pending = false
    }
  }
  Ok(())
}

///|
fn NativeLocalJournalCapture::open_original_journal(
  self : NativeLocalJournalCapture,
  original : NativeLocalJournalOriginalResources,
) -> Result[NativeLocalHostConnection, NativeLocalJournalOpenFailure] {
  if self.session.journal_open_failure is Some(failure) {
    return Err(failure)
  }
  match self.open_original_journal_stages(original) {
    Ok(host) => Ok(host)
    Err(issue) => {
      // Publish the actual DB into the original failure before clearing the
      // opening slot. A failed leave cannot discard a successfully opened DB.
      let retained = match self.opening_database {
        Some(database) => DatabasePending(database, issue)
        None => issue
      }
      let failure = self.session.retain_journal_open_failure(
        retained,
        Some(original),
      )
      self.opening_database = None
      Err(failure)
    }
  }
}

///|
fn NativeLocalJournalCapture::open_original_journal_stages(
  self : NativeLocalJournalCapture,
  original : NativeLocalJournalOriginalResources,
) -> Result[NativeLocalHostConnection, NativeLocalAdoptionIssue] {
  if !self.session.existing_only ||
    !valid_local_journal_options(
      self.ttl_ms,
      self.max_records,
      self.max_snapshot_bytes,
    ) {
    return Err(InvalidInput)
  }
  let library = match original.host.borrow_local_host_sqlite(original.pair) {
    Err(issue) => return Err(OriginalResources(issue))
    Ok(value) => value
  }
  let (ownership, adoption_body, marker) = match
    original.stage(@arena.HostRead, fn() {
      match self.session.require_current_original_read_roots() {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let (ownership, body) = match
        self.session.prepare_journal_file(self.crypto) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      self.session
      .prepare_journal_marker(ownership, body)
      .map(first => (ownership, body, first))
    }) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // Existing-only marker admission cannot select initial schema/key capture.
  // Retained inspection still uses the original SQLite Owner and full audit.
  let first = if marker {
    return Err(CustodyLost)
  } else {
    match
      original.stage(@arena.HostSqlite, fn() {
        self.session.inspect_retained_journal(
          library,
          self.max_snapshot_bytes,
          self.max_records,
        )
      }) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
  }
  match
    original.stage(@arena.HostRead, fn() { self.session.check_original() }) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let database = match
    original.stage(@arena.HostSqlite, fn() {
      match
        library.open_existing_database(
          self.session.state_path + "/client.sqlite3",
          131072L,
        ) {
        Err(issue) => Err(Physical(issue))
        Ok(database) => {
          self.opening_database = Some(database)
          Ok(database)
        }
      }
    }) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match
    original.stage(@arena.HostRead, fn() { self.session.check_original() }) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (epoch, journal) = match
    original.stage(@arena.HostSqlite, fn() {
      self.session.bind_journal_sqlite_originals(
        database,
        self.crypto,
        adoption_body,
        first,
        None,
        self.ttl_ms,
        self.max_records,
      )
    }) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let adoption_cid = match
    original.stage(@arena.HostRead, fn() {
      match self.session.check_original() {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      local_adoption_digest(self.crypto, adoption_body)
    }) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let connected : NativeLocalHostConnection = {
    session: self.session,
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
  }
  match original.check_journal_current(connected) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    original.stage(@arena.HostRead, fn() {
      connected.bootstrap_signing_originals(self.crypto, [], first)
    }) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(connected)
  }
}

///|
fn NativeLocalJournalOriginalResources::check_journal_current(
  self : NativeLocalJournalOriginalResources,
  host : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  // Runtime's current callback owns its same-pair Read bracket. An outer Read
  // here would be a nested entry. Retain the whole original fence order.
  match host.check_binding_read_prefix() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    self.stage(@arena.HostSqlite, fn() { host.check_binding_sqlite_fence() }) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    self.stage(@arena.HostRead, fn() {
      match host.session.require_current_original_read_roots() {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      host.check_binding_read_original()
    }) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.stage(@arena.HostSqlite, fn() { host.check_binding_sqlite_original() })
}

///|
fn NativeLocalJournalOriginalResources::cleanup_journal_failure(
  self : NativeLocalJournalOriginalResources,
  failure : NativeLocalJournalOpenFailure,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.finish_pending_leave() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    self.stage(
      @arena.HostRead,
      fn() { failure.cleanup_read_prefix() },
      cleanup=true,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    self.stage(
      @arena.HostSqlite,
      fn() { failure.cleanup_database() },
      cleanup=true,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.stage(
    @arena.HostRead,
    fn() { failure.acquisition.retry_cleanup() },
    cleanup=true,
  )
}

///|
fn NativeLocalJournalOriginalResources::close_journal(
  self : NativeLocalJournalOriginalResources,
  host : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  host.closed = true
  match self.finish_pending_leave() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    self.stage(
      @arena.HostSqlite,
      fn() { host.close_journal_database() },
      cleanup=true,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.stage(
    @arena.HostRead,
    fn() {
      match host.close_journal_session() {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      close_local_session_owned_root_descriptors(host.session)
    },
    cleanup=true,
  )
}

///|
fn NativeLocalJournalOriginalResources::close_unopened_session(
  self : NativeLocalJournalOriginalResources,
  session : NativeLocalAdoptionSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.finish_pending_leave() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.stage(
    @arena.HostRead,
    fn() {
      if session.close() {
        close_local_session_owned_root_descriptors(session)
      } else {
        Err(CustodyLost)
      }
    },
    cleanup=true,
  )
}
