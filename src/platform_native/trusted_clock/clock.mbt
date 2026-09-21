///|
pub(all) enum NativeTrustedClockIssue {
  InvalidConfiguration
  Rollback
  Closed
  Physical(@sqlite.NativeSqliteIssue)
}

///|
pub struct NativeTrustedClock {
  database : @sqlite.Database
  scope : String
  key : String
  mut closed : Bool
}

///|
pub fn open(
  library : @sqlite.Library,
  path : String,
  scope : String,
  key : String,
) -> Result[NativeTrustedClock, NativeTrustedClockIssue] {
  if path.is_empty() ||
    scope.is_empty() ||
    key.is_empty() ||
    scope.length() > 256 ||
    key.length() > 256 {
    return Err(InvalidConfiguration)
  }
  match library.open_database(path, 4096L) {
    Ok(database) => Ok({ database, scope, key, closed: false, })
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn parse_nonnegative(value : Bytes) -> Int64? {
  let text = @utf8.decode(value) catch { _ => return None }
  let parsed : Int64 = @string.from_str(text) catch { _ => return None }
  if parsed < 0L {
    None
  } else {
    Some(parsed)
  }
}

///|
pub fn advance_lower_bound(
  database : @sqlite.Database,
  scope : String,
  key : String,
  observed : Int64,
) -> Result[Int64, NativeTrustedClockIssue] {
  if scope.is_empty() || key.is_empty() || observed < 0L {
    return Err(Rollback)
  }
  let body = @utf8.encode(observed.to_string())
  for attempt = 0; attempt < 8; attempt = attempt + 1 {
    match database.read(scope, key) {
      Ok(existing) => {
        let previous = match parse_nonnegative(existing.body) {
          Some(value) => value
          None => return Err(Physical(@sqlite.Collision))
        }
        if observed < previous {
          return Err(Rollback)
        }
        if observed == previous {
          return Ok(observed)
        }
        match database.compare_exchange(scope, key, existing.revision, body) {
          Ok(_) => return Ok(observed)
          Err(@sqlite.Collision) | Err(@sqlite.Busy) => continue
          Err(issue) => return Err(Physical(issue))
        }
      }
      Err(@sqlite.NotFound) =>
        match database.insert(scope, key, body) {
          Ok(_) => return Ok(observed)
          Err(@sqlite.Collision) | Err(@sqlite.Busy) => continue
          Err(issue) => return Err(Physical(issue))
        }
      Err(issue) => return Err(Physical(issue))
    }
  }
  Err(Physical(@sqlite.Busy))
}

///|
fn NativeTrustedClock::observe_value(
  self : NativeTrustedClock,
  observed : Int64,
) -> Result[Int64, NativeTrustedClockIssue] {
  if self.closed {
    return Err(Closed)
  }
  advance_lower_bound(self.database, self.scope, self.key, observed)
}

///|
/// Returns a host-clock observation only after durably enforcing the
/// monotonic lower bound for this authority scope.
pub fn NativeTrustedClock::observe(
  self : NativeTrustedClock,
) -> Result[Int64, NativeTrustedClockIssue] {
  self.observe_value(@env.now().reinterpret_as_int64())
}

///|
pub fn NativeTrustedClock::close(self : NativeTrustedClock) -> Bool {
  if self.closed {
    return true
  }
  self.closed = true
  self.database.close()
  true
}
