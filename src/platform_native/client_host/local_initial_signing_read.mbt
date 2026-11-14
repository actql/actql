///|
// Borrow the existing operation's SAME material, never its Account decision.
// Clearing facts or entering another Read retires this exact material identity.
// A missing context retains the legacy full fence; an expired one never falls
// back to it and cannot turn a later operation into this original Read.
fn NativeLocalHostConnection::check_signing_original_read(
  self : NativeLocalHostConnection,
  original_read : (
    NativeLocalJournalCapture,
    @host.ClientLocalAdoptedHostMaterial[
      @sqlite.Database,
      NativeLocalAdoptionIssue,
    ],
  )?,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard original_read is Some((capture, material)) else {
    return self.check_binding()
  }
  if capture.read_operation_issue is Some(issue) {
    return Err(issue)
  }
  guard capture.opening is JournalAcquired(actual) &&
    physical_equal(actual, self) &&
    capture.read_callback_active &&
    capture.read_facts_valid &&
    capture.read_material is Some(retained) &&
    physical_equal(retained, material) else {
    return Err(OriginalResourceScopePending)
  }
  // This diagnostic observes only the existing calls. It never performs a
  // second current probe or makes the result depend on a measured count.
  let source_before = native_timing_counter_value(37)
  let package_before = if source_before >= 0L {
    native_timing_counter_value(59)
  } else {
    -1L
  }
  let digest_before = if source_before >= 0L {
    native_timing_counter_value(26)
  } else {
    -1L
  }
  let material_before = if source_before >= 0L {
    native_timing_counter_value(33)
  } else {
    -1L
  }
  let result = capture.with_current_adoption_material_in_original_read((
    actual,
    current,
    _,
  ) => {
    if !physical_equal(actual, self) || !physical_equal(current, material) {
      return Err(CustodyLost)
    }
    match self.check_binding_sqlite_fence() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    // Physical database replacement remains distinct from immutable admission.
    self.check_database_file_original()
  })
  if source_before >= 0L &&
    (
      native_timing_counter_value(37) != source_before ||
      native_timing_counter_value(59) != package_before ||
      native_timing_counter_value(26) != digest_before ||
      native_timing_counter_value(33) != material_before
    ) {
    native_timing_count(65)
  }
  result
}

///|
fn NativeLocalInitialSigningOriginal::check_host_current(
  self : NativeLocalInitialSigningOriginal,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  self.host.check_signing_original_read(self.original_read)
}

///|
// Consume the existing closed after-current frame. This is a physical
// Read/material/Library identity check, not a new source audit or grant.
fn NativeLocalInitialSigningOriginal::check_initial_control_read_scope(
  self : NativeLocalInitialSigningOriginal,
  host : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if !physical_equal(self.host, host) ||
    !physical_equal(host.epoch.database, host.database) {
    return Err(CustodyLost)
  }
  guard self.original_read is Some((capture, material)) else {
    return Err(OriginalResourceScopePending)
  }
  if capture.read_operation_issue is Some(issue) {
    return Err(issue)
  }
  guard capture.opening is JournalAcquired(actual_host) &&
    physical_equal(actual_host, host) &&
    capture.read_callback_active &&
    capture.read_facts_valid &&
    capture.read_material is Some(actual_material) &&
    physical_equal(actual_material, material) &&
    host.epoch.operation_active else {
    return Err(OriginalResourceScopePending)
  }
  match capture.check_original_read_lifetime() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  host.epoch.crypto.require_current().map_err(issue => Crypto(issue))
}

///|
// A real external callback or physical signing boundary requires the full
// original observation again. Failure spends the scoped facts, never the
// signing claim or the original physical cleanup obligation.
fn NativeLocalInitialSigningOriginal::check_callback_current(
  self : NativeLocalInitialSigningOriginal,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.original_read is None {
    return self.host.check_binding()
  }
  match self.check_host_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Existing diagnostic table, dedicated slot: count this actual external /
  // physical boundary, not immutable helper calls or Account outcomes.
  native_timing_count(64)
  // An observation made before an external callback/physical sign cannot
  // authenticate a control after it. Drop the same Owner's observation and
  // freshly sample only AFTER the complete boundary fence succeeds.
  self.host.epoch.invalidate_custody()
  let current = match self.host.check_binding() {
    Err(issue) => Err(issue)
    Ok(_) =>
      match self.host.epoch.require_operation_current(None) {
        Err(issue) => Err(Epoch(issue))
        Ok(_) =>
          self.host.epoch
          .custody(None)
          .map(_ => ())
          .map_err(issue => Epoch(issue))
      }
  }
  match current {
    Err(issue) => {
      if self.original_read is Some((capture, _)) {
        if capture.read_operation_issue is None {
          capture.read_operation_issue = Some(issue)
        }
        capture.read_facts_valid = false
        capture.clear_read_operation_facts()
      }
      Err(issue)
    }
    Ok(_) => self.check_host_current()
  }
}

///|
fn NativeLocalInitialSigningOriginal::selected_configuration(
  self : NativeLocalInitialSigningOriginal,
  name : String,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  guard self.original_read is Some((capture, _)) else {
    return self.host.selected_configuration(name)
  }
  match self.check_host_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  capture.selected_configuration_in_original_read(name)
}

///|
fn NativeLocalInitialSigningOriginal::authority_scope_cid(
  self : NativeLocalInitialSigningOriginal,
  principal : String,
  connection : String,
) -> Result[String, NativeLocalAdoptionIssue] {
  guard self.original_read is Some((capture, _)) else {
    return self.host.authority_scope_cid(
      principal,
      connection,
      self.host.epoch.crypto,
    )
  }
  match self.check_host_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  capture.authority_scope_cid_in_original_read(principal, connection)
}

///|
// Only this active original Read may project the already-admitted raw-file
// CID. The enclosing key/account checks keep their independent current roles.
// Omitted legacy scope retains the complete original digest computation.
fn NativeLocalInitialSigningOriginal::selected_configuration_cid_after_current(
  self : NativeLocalInitialSigningOriginal,
  name : String,
  body : Bytes,
) -> Result[String, NativeLocalAdoptionIssue] {
  if self.original_read is None {
    return local_adoption_digest(self.host.epoch.crypto, body)
  }
  match self.check_initial_control_read_scope(self.host) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.host.selected_configuration_cid_after_current(name, body)
}

///|
// Keep every role's Account evaluation fresh. The existing operation's cached
// read decision is deliberately not consulted for Reviewer resolve or Host sign.
fn NativeLocalInitialSigningOriginal::authorize(
  self : NativeLocalInitialSigningOriginal,
  tuple : @authorization.AccessTuple,
) -> Result[@authorization.AccountOutcome, NativeLocalAdoptionIssue] {
  guard self.original_read is Some((capture, material)) else {
    return self.host.authorize(tuple)
  }
  match self.check_host_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  capture.with_current_adoption_material_in_original_read((actual, current, _) => {
    if !physical_equal(actual, self.host) || !physical_equal(current, material) {
      return Err(CustodyLost)
    }
    native_timing_count(35)
    @host.client_local_adopted_account_outcome(current, actual.database, tuple).map_err(
      local_current_material_issue,
    )
  })
}
