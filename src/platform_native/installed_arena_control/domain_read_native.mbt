///|
/// Existing installed Host/domain only. This lends no new bytes or authority;
/// the original domain retains the one-shot Common use and physical context.
pub fn InstalledArenaHost::prepare_domain_read(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
  execution_ceiling? : Int64,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.require_domain_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.backing.prepare_backed_read_context(
    self,
    record.domain.unwrap(),
    record,
    execution_ceiling?,
  )
}

///|
pub fn InstalledArenaHost::require_domain_read_current(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.require_domain_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.backing.require_backed_read_context_current(
    self,
    record.domain.unwrap(),
    record,
  )
}

///|
/// Surround the whole managed caller, including values/failure carriers. The
/// same C provider exposes only its active context to the filesystem wrapper.
pub fn InstalledArenaHost::enter_domain_read(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.require_domain_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  record.backing.enter_backed_read_context(self, record.domain.unwrap(), record)
}

///|
/// Cleanup uses its same registered original even after logical Host closing.
/// This checks identity, not successful cleanup or fresh read permission.
fn InstalledArenaHost::original_read_domain(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[
  @bootstrap.NativeBackedExecutionDomain[
    InstalledArenaHost,
    InstalledArenaDomain,
  ],
  @bootstrap.NativeBackedExecutionIssue,
] {
  if !physical_equal(record.host, self) ||
    record.closed ||
    self.closed ||
    !self.domains.any(original => physical_equal(original, record)) {
    return Err(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))
  }
  guard self.backing is Some(backing) &&
    physical_equal(backing, record.backing) &&
    record.domain is Some(domain) else {
    return Err(@bootstrap.Bootstrap(@bootstrap.Unavailable))
  }
  Ok(domain)
}

///|
pub fn InstalledArenaHost::enter_domain_read_cleanup(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.original_read_domain(record) {
    Err(issue) => Err(issue)
    Ok(domain) => record.backing.enter_backed_read_cleanup(self, domain, record)
  }
}

///|
pub fn InstalledArenaHost::leave_domain_read(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.original_read_domain(record) {
    Err(issue) => Err(issue)
    Ok(domain) => record.backing.leave_backed_read_context(self, domain, record)
  }
}

///|
/// Actual context/users/alias retirement, then only the extra Common borrow.
/// Full domain/view/FD/worker cleanup remains with the existing original Owner.
pub fn InstalledArenaHost::close_domain_read(
  self : InstalledArenaHost,
  record : InstalledArenaDomain,
) -> Result[Unit, @bootstrap.NativeBackedExecutionIssue] {
  match self.original_read_domain(record) {
    Err(issue) => Err(issue)
    Ok(domain) => {
      if record.crypto_component is Some(component) && !component.closed {
        return Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
      }
      if record.sqlite_library is Some(library) && !library.closed {
        return Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
      }
      if record.original_read is Some(read) && !read.closed {
        return Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
      }
      record.backing.close_backed_read_context(self, domain, record)
    }
  }
}
