///|
/// Original installed Host/domain custody only. No path, heap declaration or
/// loaded Library grants installed trust, Store authority or a normal profile.
pub(all) enum InstalledArenaSqliteIssue {
  Domain(@bootstrap.NativeBackedExecutionIssue)
  Library(@sqlite.NativeSqliteIssue)
}

///|
/// Registered before the foreign call. The same domain retains successful and
/// partial Library references until their own cleanup and scope-leave ACKs.
struct InstalledArenaSqliteLibrary {
  domain : InstalledArenaDomain
  mut library : @sqlite.Library?
  mut failure : @sqlite.NativeSqliteLibraryLoadFailure?
  mut database : InstalledArenaSqliteDatabase?
  mut failed : Bool
  mut scope_open : Bool
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaSqliteAcquisition {
  ReadySqlite(InstalledArenaSqliteLibrary)
  PendingSqlite(InstalledArenaSqliteLibrary, InstalledArenaSqliteIssue)
}

///|
fn first_sqlite_issue(
  original : InstalledArenaSqliteIssue?,
  issue : InstalledArenaSqliteIssue,
) -> InstalledArenaSqliteIssue? {
  match original {
    Some(_) => original
    None => Some(issue)
  }
}

///|
fn InstalledArenaHost::original_sqlite_library(
  self : InstalledArenaHost,
  record : InstalledArenaSqliteLibrary,
) -> Result[Unit, InstalledArenaSqliteIssue] {
  if !physical_equal(record.domain.host, self) ||
    !self.domains.any(domain => physical_equal(domain, record.domain)) ||
    !(record.domain.sqlite_library is Some(original) &&
    physical_equal(original, record)) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
  }
  Ok(())
}

///|
/// Trusted installed caller first verifies component/cohort and the original
/// Host/Store epoch. This method binds only its nominal domain/current/custody;
/// it does not invent the absent installer or complete VM funding supplier.
pub fn InstalledArenaHost::prepare_sqlite_library(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  path : String,
  heap_bytes : Int64,
  diagnostic_ceiling : Int,
  command_member? : @filesystem.NativeObservedComponentMember? = None,
) -> Result[InstalledArenaSqliteAcquisition, InstalledArenaSqliteIssue] {
  match self.require_domain_read_current(domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if domain.crypto_component is Some(_) ||
    domain.sqlite_library is Some(_) ||
    domain.original_read is Some(_) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)))
  }
  let record : InstalledArenaSqliteLibrary = {
    domain,
    library: None,
    failure: None,
    database: None,
    failed: false,
    scope_open: false,
    closed: false,
  }
  domain.sqlite_library = Some(record)
  // The actual first issue is returned unchanged, and a partial Library keeps
  // its own original failure. Do not retain child-allocated diagnostic enums
  // in this persistent controller after its Library cleanup is acknowledged.
  let mut primary_issue : InstalledArenaSqliteIssue? = None
  match self.enter_domain_read(domain) {
    Err(issue) =>
      primary_issue = first_sqlite_issue(primary_issue, Domain(issue))
    Ok(_) => {
      record.scope_open = true
      match
        @sqlite.load_current_component_with_custody(
          path, heap_bytes, diagnostic_ceiling, command_member~,
        ) {
        Ok(library) => record.library = Some(library)
        Err(@sqlite.RefusedBeforeAcquisition(issue)) =>
          primary_issue = first_sqlite_issue(primary_issue, Library(issue))
        Err(@sqlite.CleanupRequired(failure)) => {
          record.failure = Some(failure)
          primary_issue = first_sqlite_issue(
            primary_issue,
            Library(failure.issue()),
          )
        }
      }
      // A successful foreign result cannot replace the original current fence.
      match self.require_domain_read_current(domain) {
        Err(issue) =>
          primary_issue = first_sqlite_issue(primary_issue, Domain(issue))
        Ok(_) => ()
      }
      match self.leave_domain_read(domain) {
        Err(issue) =>
          primary_issue = first_sqlite_issue(primary_issue, Domain(issue))
        Ok(_) => record.scope_open = false
      }
    }
  }
  record.failed = primary_issue is Some(_)
  match primary_issue {
    Some(issue) => Ok(PendingSqlite(record, issue))
    None => Ok(ReadySqlite(record))
  }
}

///|
/// Read access is separately fenced. Cleanup remains possible after Host
/// logical closing; a copied/foreign carrier or closed domain is never usable.
pub fn InstalledArenaHost::current_sqlite_library(
  self : InstalledArenaHost,
  record : InstalledArenaSqliteLibrary,
) -> Result[@sqlite.Library, InstalledArenaSqliteIssue] {
  match self.original_sqlite_library(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.require_domain_read_current(record.domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if record.closed || record.scope_open || record.failed {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  match record.library {
    Some(library) => Ok(library)
    None => Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
}

///|
/// Same checked Library/partial carrier, then leave ACK. No reload, rebind,
/// replacement domain or domain/loan retirement is performed here.
pub fn InstalledArenaHost::close_sqlite_library(
  self : InstalledArenaHost,
  record : InstalledArenaSqliteLibrary,
) -> Result[Unit, InstalledArenaSqliteIssue] {
  match self.original_sqlite_library(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.closed {
    return Ok(())
  }
  // A live or failed-open Database retains this exact Library. Do not stop
  // its Common read use merely because a parent close was requested.
  if record.database is Some(original) && !original.closed {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  if record.scope_open {
    match self.leave_domain_read(record.domain) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => record.scope_open = false
    }
  }
  if record.library is None && record.failure is None {
    record.database = None
    record.closed = true
    return Ok(())
  }
  match self.enter_domain_read_cleanup(record.domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => record.scope_open = true
  }
  let cleanup = match record.library {
    Some(library) =>
      match library.close_checked() {
        Ok(_) => {
          record.library = None
          Ok(())
        }
        Err(issue) => Err(Library(issue))
      }
    None =>
      match record.failure {
        Some(failure) =>
          match failure.retry_cleanup() {
            Ok(_) => {
              record.failure = None
              Ok(())
            }
            Err(issue) => Err(Library(issue))
          }
        None => Ok(())
      }
  }
  let leave = self.leave_domain_read(record.domain)
  if leave is Ok(_) {
    record.scope_open = false
  }
  match cleanup {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match leave {
    Err(issue) => Err(Domain(issue))
    Ok(_) => {
      record.database = None
      record.closed = true
      Ok(())
    }
  }
}
