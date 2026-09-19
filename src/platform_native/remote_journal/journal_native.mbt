///|
struct Journal {
  database : @sqlite.Database
  control : @remote.SiteDispatchJournal
  mut closed : Bool
}

///|
pub fn open_journal(
  library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  control : @remote.SiteDispatchJournal,
) -> Result[Journal, NativeRemoteJournalIssue] {
  match library.open_database(path, max_record_bytes) {
    Ok(database) => Ok({ database, control, closed: false, })
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn Journal::existing(
  self : Journal,
  request : @remote.DispatchRequest,
  value : @sqlite.NativeJournalValue,
) -> Result[
  (@remote.DispatchAcceptance, @remote.DispatchRecord),
  NativeRemoteJournalIssue,
] {
  let durable = match @remote.admit_durable_dispatch_record(value.body) {
    Ok(record) => record
    Err(issue) => return Err(Protocol(issue))
  }
  if value.revision !=
    @remote.durable_dispatch_record_revision(durable).to_int64() ||
    @remote.durable_dispatch_record_request_identity(durable) !=
    @remote.dispatch_request_identity(request) {
    return Err(StateCollision)
  }
  match @remote.restore_durable_dispatch_record(self.control, durable) {
    Ok(_) => ()
    Err(issue) => return Err(Protocol(issue))
  }
  let admission = match
    @remote.prepare_dispatch_acceptance(self.control, request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match @remote.commit_dispatch_acceptance(admission, true) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Protocol(issue))
  }
}

///|
pub fn Journal::accept(
  self : Journal,
  request : @remote.DispatchRequest,
) -> Result[
  (@remote.DispatchAcceptance, @remote.DispatchRecord),
  NativeRemoteJournalIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match self.database.read("site_dispatch", key) {
    Ok(value) => self.existing(request, value)
    Err(@sqlite.NotFound) => {
      let admission = match
        @remote.prepare_dispatch_acceptance(self.control, request) {
        Ok(value) => value
        Err(issue) => return Err(Protocol(issue))
      }
      let body = match @remote.dispatch_admission_durable_json(admission) {
        Ok(value) => @utf8.encode(value)
        Err(issue) => return Err(Protocol(issue))
      }
      match self.database.insert("site_dispatch", key, body) {
        Ok(revision) => {
          if revision != 0L {
            return Err(StateCollision)
          }
          match @remote.commit_dispatch_acceptance(admission, true) {
            Ok(value) => Ok(value)
            Err(issue) => Err(Protocol(issue))
          }
        }
        Err(@sqlite.Collision) =>
          match self.database.read("site_dispatch", key) {
            Ok(value) => self.existing(request, value)
            Err(issue) => Err(Physical(issue))
          }
        Err(issue) => Err(Physical(issue))
      }
    }
    Err(issue) => Err(Physical(issue))
  }
}

///|
/// Restores the next durable dispatch after the supplied journal cursor.
/// Returning one record at a time keeps restart recovery bounded.
pub fn Journal::recover_after(
  self : Journal,
  after_key : String,
) -> Result[(String, @remote.DispatchRecord)?, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let entry = match self.database.scan_after("site_dispatch", after_key) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok(None)
    Err(issue) => return Err(Physical(issue))
  }
  let durable = match @remote.admit_durable_dispatch_record(entry.body) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let expected_key = match
    @remote.durable_dispatch_record_attempt_identity(durable) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  if entry.key != expected_key ||
    entry.revision !=
    @remote.durable_dispatch_record_revision(durable).to_int64() {
    return Err(StateCollision)
  }
  match @remote.restore_durable_dispatch_record(self.control, durable) {
    Ok(record) => Ok(Some((entry.key, record)))
    Err(issue) => Err(Protocol(issue))
  }
}

///|
pub fn Journal::commit_transition(
  self : Journal,
  transition : @remote.DispatchTransition,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @remote.dispatch_transition_attempt_identity(transition) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let expected = @remote.dispatch_transition_expected_revision(transition)
  let body = match @remote.dispatch_transition_durable_json(transition) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let encoded = @utf8.encode(body)
  let durable = match
    self.database.compare_exchange(
      "site_dispatch",
      key,
      expected.to_int64(),
      encoded,
    ) {
    Ok(revision) => revision == expected.to_int64() + 1L
    Err(@sqlite.Collision) =>
      match self.database.read("site_dispatch", key) {
        Ok(value) =>
          value.revision == expected.to_int64() + 1L && value.body == encoded
        Err(issue) => return Err(Physical(issue))
      }
    Err(issue) => return Err(Physical(issue))
  }
  if !durable {
    return Err(StateCollision)
  }
  match @remote.commit_dispatch_transition(transition, true) {
    Ok(_) => Ok(())
    Err(issue) => Err(Protocol(issue))
  }
}

///|
pub fn Journal::close(self : Journal) -> Bool {
  if self.closed {
    return false
  }
  self.database.close()
  self.closed = true
  true
}
