///|
// These physical stages have one semantic source. The legacy public fence runs
// all four in order; a scoped consumer must bracket each actual Read/SQLite
// stage with the original resource Owner, without skipping or caching a check.
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
  // Staging keeps its original terminal check, and every Common/current caller
  // still invokes this complete binding fence before and after its own work.
  match self.session.stage_configuration_after_original() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
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
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.session.settings.check_retained(self.database) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  local_adoption_row(self.database, self.adoption_body)
}
