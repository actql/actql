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
  capture.with_current_adoption_material_in_original_read((actual, current, _) => {
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
}

///|
fn NativeLocalInitialSigningOriginal::check_host_current(
  self : NativeLocalInitialSigningOriginal,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  self.host.check_signing_original_read(self.original_read)
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
  match self.host.check_binding() {
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
