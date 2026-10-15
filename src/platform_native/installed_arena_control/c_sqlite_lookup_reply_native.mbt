///|
/// A start reply retains even a pending controller. Scalar/Python transport
/// success cannot manufacture its nominal registration or physical readiness.
pub fn start_installed_sqlite_lookup_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
) -> InstalledArenaSqliteDatabaseReply {
  let (lookup, issue, stage) = match host.prepare_sqlite_lookup(original) {
    Err(issue) => (None, Some(issue), 0)
    Ok(ReadySqliteLookup(child)) => (Some(child), None, 1)
    Ok(PendingSqliteLookup(child, issue)) => (Some(child), Some(issue), 1)
  }
  {
    operation: 22,
    host: original.library.domain.host,
    library: original.library,
    original: Some(original),
    lookup,
    stage,
    issue,
    after: None,
    value: None,
  }
}

///|
fn sqlite_lookup_reply(
  operation : Int,
  child : InstalledArenaSqliteLookup,
  result : InstalledArenaSqliteDatabaseCall[SqliteDatabaseReplyValue],
) -> InstalledArenaSqliteDatabaseReply {
  let (stage, value, issue, after) = match result {
    RefusedDatabaseCall(issue) => (0, None, Some(issue), None)
    ObservedDatabaseCall(Ok(value), after) => (2, Some(value), None, after)
    ObservedDatabaseCall(Err(issue), after) =>
      (2, None, Some(Library(issue)), after)
  }
  {
    operation,
    host: child.database.library.domain.host,
    library: child.database.library,
    original: Some(child.database),
    lookup: Some(child),
    stage,
    value,
    issue,
    after,
  }
}

///|
pub fn observe_installed_sqlite_lookup_reply(
  host : InstalledArenaHost,
  child : InstalledArenaSqliteLookup,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_lookup_reply(
    23,
    child,
    host.call_sqlite_lookup(child, _ => Ok(DatabaseUnit)),
  )
}

///|
pub fn read_installed_sqlite_lookup_reply(
  host : InstalledArenaHost,
  child : InstalledArenaSqliteLookup,
  scope : String,
  key : String,
  max_body_bytes : Int64,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_lookup_reply(
    24,
    child,
    host.call_sqlite_lookup(child, original => {
      match original.read_with_body_limit(scope, key, max_body_bytes) {
        Err(issue) => Err(issue)
        Ok(row) => Ok(DatabaseRow(key, row.revision, row.body))
      }
    }),
  )
}

///|
pub fn scan_installed_sqlite_lookup_reply(
  host : InstalledArenaHost,
  child : InstalledArenaSqliteLookup,
  scope : String,
  after_key : String,
  max_body_bytes : Int64,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_lookup_reply(
    25,
    child,
    host.call_sqlite_lookup(child, original => {
      match
        original.scan_after_with_body_limit(scope, after_key, max_body_bytes) {
        Err(issue) => Err(issue)
        Ok(row) => Ok(DatabaseRow(row.key, row.revision, row.body))
      }
    }),
  )
}

///|
pub fn header_installed_sqlite_lookup_reply(
  host : InstalledArenaHost,
  child : InstalledArenaSqliteLookup,
  scope : String,
  key : String,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_lookup_reply(
    26,
    child,
    host.call_sqlite_lookup(child, original => {
      match original.read_header(scope, key) {
        Err(issue) => Err(issue)
        Ok(header) => Ok(DatabaseHeader(header.revision, header.body_bytes))
      }
    }),
  )
}

///|
pub fn capacity_installed_sqlite_lookup_reply(
  host : InstalledArenaHost,
  child : InstalledArenaSqliteLookup,
  scope : String,
  key : String,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_lookup_reply(
    27,
    child,
    host.call_sqlite_lookup(child, original => {
      match original.read_capacity(scope, key) {
        Err(issue) => Err(issue)
        Ok(usage) =>
          Ok(CapacityUsage(usage.reserved_bytes, usage.reserved_objects))
      }
    }),
  )
}

///|
pub fn capacity_usage_installed_sqlite_lookup_reply(
  host : InstalledArenaHost,
  child : InstalledArenaSqliteLookup,
  scope : String,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_lookup_reply(
    28,
    child,
    host.call_sqlite_lookup(child, original => {
      match original.capacity_usage(scope) {
        Err(issue) => Err(issue)
        Ok(usage) =>
          Ok(CapacityUsage(usage.reserved_bytes, usage.reserved_objects))
      }
    }),
  )
}

///|
pub fn database_usage_installed_sqlite_lookup_reply(
  host : InstalledArenaHost,
  child : InstalledArenaSqliteLookup,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_lookup_reply(
    29,
    child,
    host.call_sqlite_lookup(child, original => {
      match original.database_usage() {
        Err(issue) => Err(issue)
        Ok(usage) =>
          Ok(
            DatabaseUsage(
              usage.record_count,
              usage.body_bytes,
              usage.reservation_count,
            ),
          )
      }
    }),
  )
}

///|
pub fn finish_installed_sqlite_lookup_reply(
  host : InstalledArenaHost,
  child : InstalledArenaSqliteLookup,
) -> InstalledArenaSqliteDatabaseReply {
  let result = match host.finish_sqlite_lookup(child) {
    RefusedDatabaseCall(issue) => RefusedDatabaseCall(issue)
    ObservedDatabaseCall(Err(issue), after) =>
      ObservedDatabaseCall(Err(issue), after)
    ObservedDatabaseCall(Ok(_), after) =>
      ObservedDatabaseCall(Ok(DatabaseUnit), after)
  }
  sqlite_lookup_reply(30, child, result)
}

///|
pub fn close_installed_sqlite_lookup_reply(
  host : InstalledArenaHost,
  child : InstalledArenaSqliteLookup,
) -> InstalledArenaSqliteDatabaseReply {
  let issue = match host.close_sqlite_lookup(child) {
    Err(issue) => Some(issue)
    Ok(_) => None
  }
  {
    operation: 31,
    host: child.database.library.domain.host,
    library: child.database.library,
    original: Some(child.database),
    lookup: Some(child),
    stage: 3,
    value: None,
    issue,
    after: None,
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::original_lookup(
  self : InstalledArenaSqliteDatabaseReply,
) -> InstalledArenaSqliteLookup? {
  self.lookup
}

///|
/// Revalidate a retained row's EXACT original read child before physical copy.
/// A database-only observe is deliberately insufficient during a fenced read.
pub fn InstalledArenaSqliteDatabaseReply::revalidate_copy(
  self : InstalledArenaSqliteDatabaseReply,
) -> InstalledArenaSqliteDatabaseReply {
  match self.lookup {
    Some(child) => observe_installed_sqlite_lookup_reply(self.host, child)
    None =>
      match self.original {
        Some(database) =>
          observe_installed_sqlite_database_reply(self.host, database)
        None => self
      }
  }
}
