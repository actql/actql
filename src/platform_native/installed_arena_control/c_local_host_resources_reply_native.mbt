///|
/// Immutable operation observation retaining the actual input originals even
/// when binding fails. It neither issues a scope nor acknowledges physical I/O.
struct InstalledArenaLocalHostResourcesReply {
  operation : Int
  read : InstalledArenaOriginalRead
  sqlite : InstalledArenaSqliteLibrary
  original : InstalledArenaLocalHostResources?
  issue : InstalledArenaLocalHostResourcesIssue?
}

///|
/// Same original SharedCapacity observation only. Missing/closing is -1,
/// never zero capacity or credit. Actual allocation still goes through the
/// existing Owner; the caller's declared control envelope is not subtracted.
pub fn installed_arena_capacity_scalar(
  host : InstalledArenaHost,
  index : Int,
) -> Int64 {
  let backing = match host.original_backing() {
    Err(_) => return -1L
    Ok(backing) => backing
  }
  let usage = backing.capacity_usage()
  match index {
    0 => usage.capacity
    1 => usage.allocated
    2 => if usage.closing { 1L } else { 0L }
    _ => -1L
  }
}

///|
pub fn bind_installed_local_host_resources_reply(
  host : InstalledArenaHost,
  read : InstalledArenaOriginalRead,
  sqlite : InstalledArenaSqliteLibrary,
) -> InstalledArenaLocalHostResourcesReply {
  match host.bind_local_host_resources(read, sqlite) {
    Err(issue) =>
      { operation: 1, read, sqlite, original: None, issue: Some(issue), }
    Ok(original) =>
      { operation: 1, read, sqlite, original: Some(original), issue: None, }
  }
}

///|
/// Tags are closed at this typed Owner boundary. Unknown tags invoke no
/// operation and cannot enter, leave, close, or replace an original resource.
pub fn operate_installed_local_host_resources_reply(
  host : InstalledArenaHost,
  original : InstalledArenaLocalHostResources,
  operation : Int,
) -> InstalledArenaLocalHostResourcesReply {
  let (tag, result) = match operation {
    2 => (2, host.require_local_host_resources_current(original))
    3 => (3, host.enter_local_host_phase(original, HostRead))
    4 => (4, host.enter_local_host_phase(original, HostSqlite))
    5 => (5, host.leave_local_host_phase(original))
    6 => (6, host.enter_local_host_cleanup(original, HostRead))
    7 => (7, host.enter_local_host_cleanup(original, HostSqlite))
    8 => (8, host.close_local_host_resources(original))
    _ => (0, Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable))))
  }
  {
    operation: tag,
    read: original.read,
    sqlite: original.sqlite,
    original: Some(original),
    issue: match result {
      Ok(_) => None
      Err(issue) => Some(issue)
    },
  }
}

///|
pub fn InstalledArenaLocalHostResourcesReply::original_host(
  self : InstalledArenaLocalHostResourcesReply,
) -> InstalledArenaHost {
  self.read.domain.host
}

///|
/// A rejected foreign SQLite input keeps its own Host; the read Host is not
/// authority to close it. Getters project originals, never reconstructed IDs.
pub fn InstalledArenaLocalHostResourcesReply::sqlite_host(
  self : InstalledArenaLocalHostResourcesReply,
) -> InstalledArenaHost {
  self.sqlite.domain.host
}

///|
pub fn InstalledArenaLocalHostResourcesReply::original_read(
  self : InstalledArenaLocalHostResourcesReply,
) -> InstalledArenaOriginalRead {
  self.read
}

///|
pub fn InstalledArenaLocalHostResourcesReply::original_sqlite(
  self : InstalledArenaLocalHostResourcesReply,
) -> InstalledArenaSqliteLibrary {
  self.sqlite
}

///|
pub fn InstalledArenaLocalHostResourcesReply::original_resources(
  self : InstalledArenaLocalHostResourcesReply,
) -> InstalledArenaLocalHostResources? {
  self.original
}

///|
pub fn InstalledArenaLocalHostResourcesReply::operation_tag(
  self : InstalledArenaLocalHostResourcesReply,
) -> Int {
  self.operation
}

///|
/// The origin discriminator and nested family remain separate. In particular
/// original child Unknown is not collapsed into a known refusal or a close ACK.
pub fn InstalledArenaLocalHostResourcesReply::issue_origin(
  self : InstalledArenaLocalHostResourcesReply,
) -> Int {
  match self.issue {
    None => 0
    Some(Domain(_)) => 1
    Some(Read(_)) => 2
    Some(Sqlite(_)) => 3
  }
}

///|
pub fn InstalledArenaLocalHostResourcesReply::issue_family(
  self : InstalledArenaLocalHostResourcesReply,
) -> Int {
  match self.issue {
    None => 0
    Some(Domain(@bootstrap.Bootstrap(issue))) =>
      installed_arena_issue_family(Some(issue))
    Some(Domain(@bootstrap.Accounting(_))) => 8
    Some(Read(issue)) => original_read_issue_family(Some(issue))
    Some(Sqlite(issue)) => sqlite_reply_issue_family(Some(issue))
  }
}

///|
/// Only this same-original Close observation can support releasing transport
/// data. It does not retire either domain, FD/backing or a remote operation.
pub fn InstalledArenaLocalHostResourcesReply::close_confirmed(
  self : InstalledArenaLocalHostResourcesReply,
) -> Bool {
  self.operation == 8 &&
  self.issue is None &&
  self.original is Some(original) &&
  original.closed
}
