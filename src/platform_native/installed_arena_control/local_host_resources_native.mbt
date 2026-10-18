///|
/// A same-Host assembly of two already acquired, disjoint original domains.
/// It issues neither domain, capacity, installation trust nor Store authority.
struct InstalledArenaLocalHostResources {
  host : InstalledArenaHost
  read : InstalledArenaOriginalRead
  sqlite : InstalledArenaSqliteLibrary
  mut active : InstalledArenaLocalHostPhase?
  mut sqlite_context_retired : Bool
  mut closing : Bool
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaLocalHostPhase {
  HostRead
  HostSqlite
} derive(Eq)

///|
pub(all) enum InstalledArenaLocalHostResourcesIssue {
  Read(InstalledArenaOriginalReadIssue)
  Sqlite(InstalledArenaSqliteIssue)
  Domain(@bootstrap.NativeBackedExecutionIssue)
}

///|
fn InstalledArenaHost::original_local_host_resources(
  self : InstalledArenaHost,
  record : InstalledArenaLocalHostResources,
) -> Result[Unit, InstalledArenaLocalHostResourcesIssue] {
  if !physical_equal(record.host, self) ||
    !(self.local_host_resources is Some(original) &&
    physical_equal(original, record)) ||
    !physical_equal(record.read.domain.host, self) ||
    !physical_equal(record.sqlite.domain.host, self) ||
    physical_equal(record.read.domain, record.sqlite.domain) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
  }
  Ok(())
}

///|
/// Only the trusted installed assembly calls this, after independently
/// acquiring both originals under the same provider/backing. Equal metadata
/// or a Library path cannot replace either nominal registration/current check.
pub fn InstalledArenaHost::bind_local_host_resources(
  self : InstalledArenaHost,
  read : InstalledArenaOriginalRead,
  sqlite : InstalledArenaSqliteLibrary,
) -> Result[
  InstalledArenaLocalHostResources,
  InstalledArenaLocalHostResourcesIssue,
] {
  if self.local_host_resources is Some(_) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)))
  }
  if physical_equal(read.domain, sqlite.domain) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
  }
  match self.require_domain_original_read_current(read) {
    Err(issue) => return Err(Read(issue))
    Ok(_) => ()
  }
  match self.current_sqlite_library(sqlite) {
    Err(issue) => return Err(Sqlite(issue))
    Ok(_) => ()
  }
  let record : InstalledArenaLocalHostResources = {
    host: self,
    read,
    sqlite,
    active: None,
    sqlite_context_retired: false,
    closing: false,
    closed: false,
  }
  self.local_host_resources = Some(record)
  Ok(record)
}

///|
pub fn InstalledArenaHost::require_local_host_resources_current(
  self : InstalledArenaHost,
  record : InstalledArenaLocalHostResources,
) -> Result[Unit, InstalledArenaLocalHostResourcesIssue] {
  match self.original_local_host_resources(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.closing || record.closed {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.Closing)))
  }
  match self.require_domain_original_read_current(record.read) {
    Err(issue) => return Err(Read(issue))
    Ok(_) => ()
  }
  match self.current_sqlite_library(record.sqlite) {
    Err(issue) => return Err(Sqlite(issue))
    Ok(_) => ()
  }
  Ok(())
}

///|
/// An operation must select its actual original allocation domain. There is
/// no whole-call context, ambient fallback, nested switch or reentrant entry.
pub fn InstalledArenaHost::enter_local_host_phase(
  self : InstalledArenaHost,
  record : InstalledArenaLocalHostResources,
  phase : InstalledArenaLocalHostPhase,
) -> Result[Unit, InstalledArenaLocalHostResourcesIssue] {
  match self.require_local_host_resources_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.active is Some(_) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)))
  }
  match phase {
    HostRead =>
      match self.enter_domain_original_read(record.read) {
        Err(issue) => return Err(Read(issue))
        Ok(_) => ()
      }
    HostSqlite =>
      match self.enter_domain_read(record.sqlite.domain) {
        Err(issue) => return Err(Domain(issue))
        Ok(_) => ()
      }
  }
  record.active = Some(phase)
  Ok(())
}

///|
/// Original cleanup remains available after logical closing, without issuing
/// another read or changing either context's original retained users.
pub fn InstalledArenaHost::enter_local_host_cleanup(
  self : InstalledArenaHost,
  record : InstalledArenaLocalHostResources,
  phase : InstalledArenaLocalHostPhase,
) -> Result[Unit, InstalledArenaLocalHostResourcesIssue] {
  match self.original_local_host_resources(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.closed || record.active is Some(_) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  record.closing = true
  match phase {
    HostRead =>
      match self.enter_domain_original_read_cleanup(record.read) {
        Err(issue) => return Err(Read(issue))
        Ok(_) => ()
      }
    HostSqlite => {
      if record.sqlite_context_retired {
        return Err(Domain(@bootstrap.Bootstrap(@bootstrap.Closing)))
      }
      match self.enter_domain_read_cleanup(record.sqlite.domain) {
        Err(issue) => return Err(Domain(issue))
        Ok(_) => ()
      }
    }
  }
  record.active = Some(phase)
  Ok(())
}

///|
/// A failed leave retains the exact active phase. Cleanup retries this leave,
/// not another enter, operation, Library load or Root acquisition.
pub fn InstalledArenaHost::leave_local_host_phase(
  self : InstalledArenaHost,
  record : InstalledArenaLocalHostResources,
) -> Result[Unit, InstalledArenaLocalHostResourcesIssue] {
  match self.original_local_host_resources(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard record.active is Some(phase) else {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  match phase {
    HostRead =>
      match self.leave_domain_original_read(record.read) {
        Err(issue) => return Err(Read(issue))
        Ok(_) => ()
      }
    HostSqlite =>
      match self.leave_domain_read(record.sqlite.domain) {
        Err(issue) => return Err(Domain(issue))
        Ok(_) => ()
      }
  }
  record.active = None
  Ok(())
}

///|
/// Borrow the original read/workspace pair, without a second child Ledger.
pub fn InstalledArenaHost::borrow_local_host_read(
  self : InstalledArenaHost,
  record : InstalledArenaLocalHostResources,
) -> Result[
  (
    @buffers.OriginalWorkspaceRead[InstalledArenaOriginalRead],
    @buffers.WorkspaceLoan,
  ),
  InstalledArenaLocalHostResourcesIssue,
] {
  match self.require_local_host_resources_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.borrow_domain_original_read(record.read).map_err(issue => Read(issue))
}

///|
/// Returning the Library neither enters its context nor transfers cleanup.
pub fn InstalledArenaHost::borrow_local_host_sqlite(
  self : InstalledArenaHost,
  record : InstalledArenaLocalHostResources,
) -> Result[@sqlite.Library, InstalledArenaLocalHostResourcesIssue] {
  match self.require_local_host_resources_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.current_sqlite_library(record.sqlite).map_err(issue => Sqlite(issue))
}

///|
/// The adopted Host caller first stops its original users and closes the DB
/// and Root. Their failed/partial aliases keep the physical context busy.
/// Library and read-context ACKs remain distinct; no scope leave proves either.
/// Domain/view/FD/backing retirement remains with their existing original Owner.
pub fn InstalledArenaHost::close_local_host_resources(
  self : InstalledArenaHost,
  record : InstalledArenaLocalHostResources,
) -> Result[Unit, InstalledArenaLocalHostResourcesIssue] {
  match self.original_local_host_resources(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.closed {
    return Ok(())
  }
  record.closing = true
  if record.active is Some(_) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  match self.close_sqlite_library(record.sqlite) {
    Err(issue) => return Err(Sqlite(issue))
    Ok(_) => ()
  }
  if !record.sqlite_context_retired {
    match self.close_domain_read(record.sqlite.domain) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => record.sqlite_context_retired = true
    }
  }
  match self.close_domain_original_read(record.read) {
    Err(issue) => return Err(Read(issue))
    Ok(_) => ()
  }
  record.closed = true
  Ok(())
}
