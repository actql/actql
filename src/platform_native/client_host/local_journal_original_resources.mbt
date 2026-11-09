///|
// Retained originals inside the existing Journal capture, not another resource
// Owner. Only an actual successful enter sets active_phase; only its original
// physical leave clears it. An interrupted exchange stays cleanup-only.
priv struct NativeLocalJournalOriginalResources {
  host : @arena.InstalledArenaHost
  pair : @arena.InstalledArenaLocalHostResources
  read : @arena.InstalledArenaOriginalRead
  mut active_phase : @arena.InstalledArenaLocalHostPhase?
  mut interrupted : Bool
  // One existing original flight, retained through a failed switch.
  mut store_operation : NativeLocalStoreOperationReceiver?
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
    original_resources: Some({
      host,
      pair,
      read,
      active_phase: None,
      interrupted: false,
      store_operation: None,
    }),
    command_preparation_journal: false,
    initial_signing: None,
    read_callback_active: false,
    read_facts_valid: false,
    read_material: None,
    read_scopes: [],
    read_decisions: [],
    read_bindings: [],
    read_committed_results: [],
    read_preimages: [],
    read_evidence: [],
    read_operation_issue: None,
    opening_database: None,
    opening_physical_failure: None,
    opening_inspection: None,
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
/// Carry the actual explicit first-initialization key and policy into the same
/// Journal capture. Only its original durable marker can select initialization;
/// retained/ambiguous originals refuse these inputs rather than regenerating.
pub fn prepare_native_local_initial_journal_capture_with_original_resources(
  session : NativeLocalAdoptionSession,
  host : @arena.InstalledArenaHost,
  pair : @arena.InstalledArenaLocalHostResources,
  read : @arena.InstalledArenaOriginalRead,
  crypto : @crypto.Library,
  material : NativeLocalInitialSigningMaterial,
  policy : @host.ClientLocalSigningBootstrapPolicy,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
) -> NativeLocalJournalCapture {
  let capture = prepare_native_local_journal_capture_with_original_resources(
    session, host, pair, read, crypto, ttl_ms, max_records, max_snapshot_bytes,
  )
  { ..capture, initial_signing: Some((material, policy)), }
}

///|
fn[T] NativeLocalJournalOriginalResources::stage(
  self : NativeLocalJournalOriginalResources,
  phase : @arena.InstalledArenaLocalHostPhase,
  operation : () -> Result[T, NativeLocalAdoptionIssue],
  cleanup? : Bool = false,
) -> Result[T, NativeLocalAdoptionIssue] {
  if self.active_phase is Some(_) || self.interrupted {
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
    Err(issue) => {
      self.interrupted = true
      return Err(OriginalResources(issue))
    }
    Ok(_) => self.active_phase = Some(phase)
  }
  let result = operation()
  if self.interrupted {
    return match result {
      Err(issue) => Err(issue)
      Ok(_) => Err(OriginalResourceScopePending)
    }
  }
  match self.host.leave_local_host_phase(self.pair) {
    Ok(_) => {
      self.active_phase = None
      result
    }
    Err(issue) => {
      self.interrupted = true
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
  if self.store_operation is Some(_) {
    return Err(OriginalResourceScopePending)
  }
  self.finish_owned_pending_leave()
}

///|
// The same flight alone may recover its pending original phase. A refused
// second receiver cannot retire the first receiver's Read, SQL or business.
fn NativeLocalJournalOriginalResources::finish_pending_store_leave(
  self : NativeLocalJournalOriginalResources,
  receiver : NativeLocalStoreOperationReceiver,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard self.store_operation is Some(original) &&
    physical_equal(original, receiver) else {
    return Err(OriginalResourceScopePending)
  }
  self.finish_owned_pending_leave()
}

///|
fn NativeLocalJournalOriginalResources::finish_owned_pending_leave(
  self : NativeLocalJournalOriginalResources,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.active_phase is Some(_) {
    match self.host.leave_local_host_phase(self.pair) {
      Err(issue) => return Err(OriginalResources(issue))
      Ok(_) => self.active_phase = None
    }
  }
  self.interrupted = false
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
      let issue = match self.opening_inspection {
        Some(inspection) => InspectionPending(None, issue, inspection)
        None => issue
      }
      let retained = match self.opening_database {
        Some(database) => DatabasePending(database, issue)
        None => issue
      }
      let failure = self.session.retain_journal_open_failure_with_resources(
        retained,
        Some(original),
        physical_open_failure=self.opening_physical_failure,
      )
      self.opening_database = None
      self.opening_physical_failure = None
      self.opening_inspection = None
      Err(failure)
    }
  }
}

///|
fn NativeLocalJournalCapture::open_original_journal_stages(
  self : NativeLocalJournalCapture,
  original : NativeLocalJournalOriginalResources,
) -> Result[NativeLocalHostConnection, NativeLocalAdoptionIssue] {
  if (!self.session.existing_only && self.initial_signing is None) ||
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
  // Only the actual original marker selects first initialization. Existing
  // Session admission and the existing-only open retain missing-state refusals.
  let first = if marker {
    if self.session.existing_only {
      return Err(CustodyLost)
    }
    true
  } else {
    // Retain the same existing-only open and original physical cleanup. A
    // normal command does not copy/audit unrelated retained business history.
    false
  }
  if !first && self.initial_signing is Some(_) {
    return Err(AmbiguousInitialization)
  }
  let database = match
    original.stage(@arena.HostSqlite, fn() {
      let opening : Result[@sqlite.Database, NativeLocalAdoptionIssue] = if self.command_preparation_journal {
        let selected = if first {
          library.initialize_owned_journal_database_with_custody(
            self.session.state_path + "/client.sqlite3",
            ownership,
            131072L,
          )
        } else {
          library.open_existing_journal_database_with_custody(
            self.session.state_path + "/client.sqlite3",
            131072L,
          )
        }
        match selected {
          Ok(database) => Ok(database)
          Err(failure) => {
            self.opening_physical_failure = Some(failure)
            Err(Physical(failure.issue()))
          }
        }
      } else {
        (if first {
          library.initialize_owned_database(
            self.session.state_path + "/client.sqlite3",
            ownership,
            131072L,
          )
        } else {
          library.open_existing_database(
            self.session.state_path + "/client.sqlite3",
            131072L,
          )
        }).map_err(issue => Physical(issue))
      }
      match opening {
        Err(issue) => Err(issue)
        Ok(database) => {
          self.opening_database = Some(database)
          Ok(database)
        }
      }
    }) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let (epoch, journal) = match
    original.bootstrap_read_stage(database, fn(bootstrap) {
      let initial = match self.initial_signing {
        None => None
        Some((material, policy)) =>
          match
            self.session.prepare_initial_signing_capture(
              material,
              policy,
              self.crypto,
              adoption_body,
            ) {
            Err(issue) => return Err(issue)
            Ok(value) => Some(value)
          }
      }
      self.session.bind_journal_sqlite_originals(
        database,
        self.crypto,
        adoption_body,
        first,
        initial,
        self.ttl_ms,
        self.max_records,
        reads=Some(bootstrap.reads),
        bootstrap=Some(bootstrap),
        opening_ownership=Some(ownership),
      )
    }) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let adoption_cid = match
    original.stage(@arena.HostRead, fn() {
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
    reviewer_signing_attempt: None,
    host_attestation_signing_attempt: None,
  }
  match original.check_opened_journal_originals(connected) {
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
// The open's source admission precedes the first database acquisition. Trusted
// Read/SQL exchanges do not create new source/configuration observations. Keep
// the actual database target, physical fence and selected retained rows here.
fn NativeLocalJournalOriginalResources::check_opened_journal_originals(
  self : NativeLocalJournalOriginalResources,
  host : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
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
      host.check_database_file_original()
    }) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.audit_read_stage(host.database, reads => {
    host.session.settings.check_retained(host.database, reads=Some(reads))
  })
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
  self.audit_read_stage(host.database, reads => {
    host.check_binding_sqlite_original(reads=Some(reads))
  })
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
      fn() {
        match failure.close_inspection_database() {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        failure.close_original_database()
      },
      cleanup=true,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    self.stage(
      @arena.HostRead,
      fn() { failure.close_inspection_snapshot() },
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
  if host.reviewer_signing_attempt is Some(_) ||
    host.host_attestation_signing_attempt is Some(_) {
    match
      self.stage(
        @arena.HostRead,
        fn() { host.close_original_signing_attempts() },
        cleanup=true,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
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
