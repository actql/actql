///|
// These physical stages have one semantic source. The legacy public fence runs
// all four in order. A scoped consumer admits these facts at its operation
// boundaries and may reuse them in the same unchanged SQLite snapshot; actual
// Read/SQLite scope and original-lifetime checks remain with their Owner.
fn NativeLocalHostConnection::check_binding_read_prefix(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.packaged_runtime is Some(binding) &&
    binding.current.check_current() is Err(_) {
    return Err(CustodyLost)
  }
  Ok(())
}

///|
fn NativeLocalHostConnection::check_binding_sqlite_fence(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.database.transaction_fenced() {
    return Err(Fenced)
  }
  Ok(())
}

///|
fn NativeLocalHostConnection::check_binding_read_original(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.session.check_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // The immediately preceding actual original check is staging's entry fence.
  // Trusted copy/custody I/O consumes that same observation; it does not repeat
  // source admission. Current callers retain this complete binding entry.
  match self.session.stage_configuration_after_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.check_database_file_original()
}

///|
// Check the actual database target after physical open without restaging the
// already admitted source/configuration. Ordinary current entry also uses it.
fn NativeLocalHostConnection::check_database_file_original(
  self : NativeLocalHostConnection,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  guard self.session.root.inspect_generation("client.sqlite3") is Ok(Some(file)) &&
    file.device == self.ownership.device &&
    file.inode == self.ownership.inode else {
    return Err(CustodyLost)
  }
  Ok(())
}

///|
fn NativeLocalHostConnection::check_binding_sqlite_original(
  self : NativeLocalHostConnection,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.session.settings.check_retained(self.database, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  local_adoption_row(self.database, self.adoption_body, reads~)
}
