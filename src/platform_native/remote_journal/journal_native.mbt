///|
struct Journal {
  database : @sqlite.Database
  control : @remote.SiteDispatchJournal
  mut closed : Bool
}

///|
struct CoordinatorJournal {
  database : @sqlite.Database
  control : @remote.CoordinatorDispatchJournal
  mut closed : Bool
}

///|
fn expected_site_binding(
  control : @remote.SiteDispatchJournal,
) -> Result[Bytes, NativeRemoteJournalIssue] {
  match @remote.site_dispatch_binding_json(control) {
    Ok(value) => Ok(@utf8.encode(value))
    Err(issue) => Err(Protocol(issue))
  }
}

///|
fn install_site_binding(
  database : @sqlite.Database,
  control : @remote.SiteDispatchJournal,
) -> Result[Unit, NativeRemoteJournalIssue] {
  let expected = match expected_site_binding(control) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match database.read("site_metadata", "binding") {
    Ok(value) =>
      if value.body == expected {
        Ok(())
      } else {
        Err(StateCollision)
      }
    Err(@sqlite.NotFound) => {
      match database.scan_after("site_dispatch", "") {
        Ok(_) => return Err(StateCollision)
        Err(@sqlite.NotFound) => ()
        Err(issue) => return Err(Physical(issue))
      }
      match database.insert("site_metadata", "binding", expected) {
        Ok(0L) => Ok(())
        Ok(_) => Err(StateCollision)
        Err(@sqlite.Collision) =>
          match database.read("site_metadata", "binding") {
            Ok(value) if value.body == expected => Ok(())
            Ok(_) => Err(StateCollision)
            Err(issue) => Err(Physical(issue))
          }
        Err(issue) => Err(Physical(issue))
      }
    }
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn open_journal(
  library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  control : @remote.SiteDispatchJournal,
) -> Result[Journal, NativeRemoteJournalIssue] {
  let database = match library.open_database(path, max_record_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  match install_site_binding(database, control) {
    Ok(_) => Ok({ database, control, closed: false, })
    Err(issue) => {
      database.close()
      Err(issue)
    }
  }
}

///|
pub fn open_coordinator_journal(
  library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  control : @remote.CoordinatorDispatchJournal,
) -> Result[CoordinatorJournal, NativeRemoteJournalIssue] {
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
/// Resolve one exact durable Site record without creating dispatch authority.
/// Historical generations remain queryable after a generation restart.
pub fn Journal::require(
  self : Journal,
  request : @remote.DispatchRequest,
) -> Result[@remote.DispatchRecord, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let value = match self.database.read("site_dispatch", key) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(StateCollision)
    Err(issue) => return Err(Physical(issue))
  }
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
    Ok(record) => Ok(record)
    Err(issue) => Err(Protocol(issue))
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
fn Journal::recover_all(
  self : Journal,
) -> Result[Unit, NativeRemoteJournalIssue] {
  let mut cursor = ""
  while true {
    let entry = match self.database.scan_after("site_dispatch", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => return Ok(())
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
      Ok(_) => ()
      Err(issue) => return Err(Protocol(issue))
    }
    cursor = entry.key
  } nobreak {
    Ok(())
  }
}

///|
/// Atomically fence the old Site generation and every nonterminal physical
/// responsibility before the replacement generation can admit work.
pub fn Journal::restart(
  self : Journal,
  replacement : @site.ExecutionSite,
) -> Result[Int, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  match self.recover_all() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let restart = match
    @remote.prepare_site_generation_restart(self.control, replacement) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let current_binding = match expected_site_binding(self.control) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let next_binding = match @remote.site_restart_next_binding_json(restart) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  let metadata = match self.database.read("site_metadata", "binding") {
    Ok(value) if value.body == current_binding => value
    Ok(_) => return Err(StateCollision)
    Err(issue) => return Err(Physical(issue))
  }
  match self.database.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  let mut physical_issue : NativeRemoteJournalIssue? = None
  let locked_metadata = self.database.read("site_metadata", "binding")
  match locked_metadata {
    Ok(value) if value.revision == metadata.revision &&
      value.body == current_binding => ()
    Ok(_) => physical_issue = Some(StateCollision)
    Err(issue) => physical_issue = Some(Physical(issue))
  }
  let count = @remote.site_restart_transition_count(restart)
  for index = 0; index < count; index = index + 1 {
    if physical_issue is Some(_) {
      continue
    }
    guard @remote.site_restart_transition_at(restart, index) is Some(transition) else {
      physical_issue = Some(StateCollision)
      continue
    }
    let key = match @remote.dispatch_transition_attempt_identity(transition) {
      Ok(value) => value
      Err(issue) => {
        physical_issue = Some(Protocol(issue))
        continue
      }
    }
    let body = match @remote.dispatch_transition_durable_json(transition) {
      Ok(value) => @utf8.encode(value)
      Err(issue) => {
        physical_issue = Some(Protocol(issue))
        continue
      }
    }
    let expected = @remote.dispatch_transition_expected_revision(transition)
    match
      self.database.compare_exchange(
        "site_dispatch",
        key,
        expected.to_int64(),
        body,
      ) {
      Ok(revision) if revision == expected.to_int64() + 1L => ()
      Ok(_) | Err(@sqlite.Collision) => physical_issue = Some(StateCollision)
      Err(issue) => physical_issue = Some(Physical(issue))
    }
  }
  if physical_issue is None {
    match
      self.database.compare_exchange(
        "site_metadata",
        "binding",
        metadata.revision,
        next_binding,
      ) {
      Ok(revision) if revision == metadata.revision + 1L => ()
      Ok(_) | Err(@sqlite.Collision) => physical_issue = Some(StateCollision)
      Err(issue) => physical_issue = Some(Physical(issue))
    }
  }
  match physical_issue {
    Some(issue) => {
      ignore(self.database.rollback())
      return Err(issue)
    }
    None => ()
  }
  match self.database.commit() {
    Ok(_) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match @remote.commit_site_generation_restart(restart, true) {
    Ok(value) => Ok(value)
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

///|
fn CoordinatorJournal::restore_entry(
  self : CoordinatorJournal,
  key : String,
  value : @sqlite.NativeJournalValue,
) -> Result[RecoveredCoordinatorDispatch, NativeRemoteJournalIssue] {
  let durable = match
    @remote.admit_durable_coordinator_dispatch_record(value.body) {
    Ok(record) => record
    Err(issue) => return Err(Protocol(issue))
  }
  let expected_key = match
    @remote.durable_coordinator_dispatch_record_attempt_identity(durable) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  if key != expected_key ||
    value.revision !=
    @remote.durable_coordinator_dispatch_record_revision(durable).to_int64() {
    return Err(StateCollision)
  }
  let record = match
    @remote.restore_durable_coordinator_dispatch_record(self.control, durable) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  Ok({
    key,
    record,
    evidence: @remote.durable_coordinator_dispatch_record_evidence(durable),
    subject: @remote.durable_coordinator_dispatch_record_subject(durable),
    measurement: @remote.durable_coordinator_dispatch_record_measurement(
      durable,
    ),
  })
}

///|
pub fn CoordinatorJournal::accept(
  self : CoordinatorJournal,
  request : @remote.DispatchRequest,
) -> Result[
  (@remote.DispatchAcceptance, @remote.CoordinatorDispatchIntentRecord),
  NativeRemoteJournalIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match self.database.read("coordinator_dispatch", key) {
    Ok(value) => {
      let recovered = match self.restore_entry(key, value) {
        Ok(item) => item
        Err(issue) => return Err(issue)
      }
      if !@remote.coordinator_dispatch_intent_matches_request(
          recovered.record,
          request,
        ) {
        return Err(StateCollision)
      }
      Ok((@remote.ExistingDispatch, recovered.record))
    }
    Err(@sqlite.NotFound) => {
      let admission = match
        @remote.prepare_coordinator_dispatch_intent(self.control, request) {
        Ok(value) => value
        Err(issue) => return Err(Protocol(issue))
      }
      let body = match
        @remote.coordinator_dispatch_admission_durable_json(admission) {
        Ok(value) => @utf8.encode(value)
        Err(issue) => return Err(Protocol(issue))
      }
      match self.database.insert("coordinator_dispatch", key, body) {
        Ok(revision) => {
          if revision != 0L {
            return Err(StateCollision)
          }
          match @remote.commit_coordinator_dispatch_intent(admission, true) {
            Ok(value) => Ok(value)
            Err(issue) => Err(Protocol(issue))
          }
        }
        Err(@sqlite.Collision) =>
          match self.database.read("coordinator_dispatch", key) {
            Ok(value) => {
              let recovered = match self.restore_entry(key, value) {
                Ok(item) => item
                Err(issue) => return Err(issue)
              }
              if !@remote.coordinator_dispatch_intent_matches_request(
                  recovered.record,
                  request,
                ) {
                return Err(StateCollision)
              }
              Ok((@remote.ExistingDispatch, recovered.record))
            }
            Err(issue) => Err(Physical(issue))
          }
        Err(issue) => Err(Physical(issue))
      }
    }
    Err(issue) => Err(Physical(issue))
  }
}

///|
/// Resolve an already durable intent without creating a new one. Query and
/// cancellation operations use this boundary so they cannot admit execution.
pub fn CoordinatorJournal::require(
  self : CoordinatorJournal,
  request : @remote.DispatchRequest,
) -> Result[@remote.CoordinatorDispatchIntentRecord, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let value = match self.database.read("coordinator_dispatch", key) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(StateCollision)
    Err(issue) => return Err(Physical(issue))
  }
  let recovered = match self.restore_entry(key, value) {
    Ok(item) => item
    Err(issue) => return Err(issue)
  }
  if !@remote.coordinator_dispatch_intent_matches_request(
      recovered.record,
      request,
    ) {
    return Err(StateCollision)
  }
  Ok(recovered.record)
}

///|
pub fn CoordinatorJournal::commit_transition(
  self : CoordinatorJournal,
  transition : @remote.CoordinatorDispatchTransition,
  evidence? : @remote.RemoteExecutionEvidence? = None,
  subject? : @remote.RemoteManagedOutputSubject? = None,
  measurement? : @remote.RemoteManagedOutputMeasurement? = None,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let key = match
    @remote.coordinator_dispatch_transition_attempt_identity(transition) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let expected = @remote.coordinator_dispatch_transition_expected_revision(
    transition,
  )
  let current_value = match self.database.read("coordinator_dispatch", key) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  if current_value.revision != expected.to_int64() {
    return Err(StateCollision)
  }
  let current = match
    @remote.admit_durable_coordinator_dispatch_record(current_value.body) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let body = match
    @remote.coordinator_dispatch_transition_durable_json(
      current,
      transition,
      evidence~,
      subject~,
      measurement~,
    ) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  let durable = match
    self.database.compare_exchange(
      "coordinator_dispatch",
      key,
      expected.to_int64(),
      body,
    ) {
    Ok(revision) => revision == expected.to_int64() + 1L
    Err(@sqlite.Collision) =>
      match self.database.read("coordinator_dispatch", key) {
        Ok(value) =>
          value.revision == expected.to_int64() + 1L && value.body == body
        Err(issue) => return Err(Physical(issue))
      }
    Err(issue) => return Err(Physical(issue))
  }
  if !durable {
    return Err(StateCollision)
  }
  match @remote.commit_coordinator_dispatch_transition(transition, true) {
    Ok(_) => Ok(())
    Err(issue) => Err(Protocol(issue))
  }
}

///|
pub fn CoordinatorJournal::recover_after(
  self : CoordinatorJournal,
  after_key : String,
) -> Result[RecoveredCoordinatorDispatch?, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  match self.database.scan_after("coordinator_dispatch", after_key) {
    Ok(entry) =>
      self
      .restore_entry(entry.key, { revision: entry.revision, body: entry.body, })
      .map(value => Some(value))
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn CoordinatorJournal::close(self : CoordinatorJournal) -> Bool {
  if self.closed {
    return false
  }
  self.database.close()
  self.closed = true
  true
}
