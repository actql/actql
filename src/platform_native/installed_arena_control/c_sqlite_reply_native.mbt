///|
/// Immutable physical operation projection. It keeps the original Host/domain
/// and partial Library carrier; transport success is not Store/funding authority.
pub(all) enum InstalledArenaSqliteOperation {
  PrepareSqlite
  ObserveSqlite
  CloseSqlite
} derive(Eq)

///|
struct InstalledArenaSqliteReply {
  operation : InstalledArenaSqliteOperation
  host : InstalledArenaHost
  domain : InstalledArenaDomain
  original : InstalledArenaSqliteLibrary?
  issue : InstalledArenaSqliteIssue?
}

///|
pub fn prepare_installed_arena_sqlite_reply(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  path : String,
  heap_bytes : Int64,
  diagnostic_ceiling : Int,
) -> InstalledArenaSqliteReply {
  let (original, issue) = match
    host.prepare_sqlite_library(domain, path, heap_bytes, diagnostic_ceiling) {
    Err(issue) => (None, Some(issue))
    Ok(ReadySqlite(original)) => (Some(original), None)
    Ok(PendingSqlite(original, issue)) => (Some(original), Some(issue))
  }
  { operation: PrepareSqlite, host: domain.host, domain, original, issue, }
}

///|
pub fn current_installed_arena_sqlite_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteLibrary,
) -> InstalledArenaSqliteReply {
  let issue = match host.current_sqlite_library(original) {
    Ok(_) => None
    Err(issue) => Some(issue)
  }
  {
    operation: ObserveSqlite,
    host: original.domain.host,
    domain: original.domain,
    original: Some(original),
    issue,
  }
}

///|
pub fn close_installed_arena_sqlite_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteLibrary,
) -> InstalledArenaSqliteReply {
  let issue = match host.close_sqlite_library(original) {
    Ok(_) => None
    Err(issue) => Some(issue)
  }
  {
    operation: CloseSqlite,
    host: original.domain.host,
    domain: original.domain,
    original: Some(original),
    issue,
  }
}

///|
pub fn InstalledArenaSqliteReply::original_host(
  self : InstalledArenaSqliteReply,
) -> InstalledArenaHost {
  self.host
}

///|
pub fn InstalledArenaSqliteReply::original_domain(
  self : InstalledArenaSqliteReply,
) -> InstalledArenaDomain {
  self.domain
}

///|
pub fn InstalledArenaSqliteReply::original_library(
  self : InstalledArenaSqliteReply,
) -> InstalledArenaSqliteLibrary? {
  self.original
}

///|
pub fn InstalledArenaSqliteReply::operation_tag(
  self : InstalledArenaSqliteReply,
) -> Int {
  match self.operation {
    PrepareSqlite => 1
    ObserveSqlite => 2
    CloseSqlite => 3
  }
}

///|
/// Closed reason categories preserve existing Native/SQLite distinctions. A
/// description is explanation only; it is never parsed for an outcome/ACK.
pub fn InstalledArenaSqliteReply::issue_family(
  self : InstalledArenaSqliteReply,
) -> Int {
  sqlite_reply_issue_family(self.issue)
}

///|
fn sqlite_reply_issue_family(issue : InstalledArenaSqliteIssue?) -> Int {
  match issue {
    None => 0
    Some(Domain(@bootstrap.Bootstrap(issue))) =>
      installed_arena_issue_family(Some(issue))
    Some(Domain(@bootstrap.Accounting(_))) => 8
    Some(Library(@sqlite.UnsupportedTarget)) => 9
    Some(Library(@sqlite.InvalidName)) => 10
    Some(Library(@sqlite.InvalidLimit)) => 11
    Some(Library(@sqlite.LibraryLoad(_))) => 12
    Some(Library(@sqlite.DatabaseOpen(_))) => 13
    Some(Library(@sqlite.DatabaseClosed)) => 14
    Some(Library(@sqlite.NotFound)) => 15
    Some(Library(@sqlite.Collision)) => 16
    Some(Library(@sqlite.Busy)) => 17
    Some(Library(@sqlite.BodyTooLarge)) => 18
    Some(Library(@sqlite.CapacityExceeded)) => 19
    Some(Library(@sqlite.Physical(_))) => 20
    Some(Library(@sqlite.OperationRoutingBefore(_))) => 21
    Some(Library(@sqlite.OperationRoutingAfter(_, _))) => 22
  }
}

///|
pub fn InstalledArenaSqliteReply::issue_description(
  self : InstalledArenaSqliteReply,
) -> String {
  match self.issue {
    None => ""
    Some(Domain(issue)) => @debug.to_string(issue)
    // Typed family carries the reason. Do not expose platform loader paths or
    // use a diagnostic string as the foreign caller's outcome discriminator.
    Some(Library(_)) => "SQLite physical operation refused"
  }
}
