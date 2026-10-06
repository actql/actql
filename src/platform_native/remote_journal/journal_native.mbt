///|
struct Journal {
  database : @sqlite.Database
  control : @remote.SiteDispatchJournal
  max_record_bytes : Int64
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
/// Start one physical mutation and, when required, fence it against the exact
/// Site binding opened by this Journal. The binding read and the caller's
/// writes share one SQLite transaction.
fn Journal::begin_mutation(
  self : Journal,
  require_current_site : Bool,
) -> Result[Unit, NativeRemoteJournalIssue] {
  match self.database.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  if !require_current_site {
    return Ok(())
  }
  let expected = match expected_site_binding(self.control) {
    Ok(value) => value
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(issue)
    }
  }
  match self.database.read("site_metadata", "binding") {
    Ok(value) if value.body == expected => Ok(())
    Ok(_) | Err(@sqlite.NotFound) => {
      ignore(self.database.rollback())
      Err(StaleSiteBinding)
    }
    Err(issue) => {
      ignore(self.database.rollback())
      Err(Physical(issue))
    }
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
    Ok(_) => Ok({ database, control, max_record_bytes, closed: false, })
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
  match inspect_coordinator_source(library, path, max_record_bytes, control) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
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
  let restored = match
    @remote.restore_durable_dispatch_record(self.control, durable) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let key = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match self.restore_observation(restored, key) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
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
fn Journal::restore_observation(
  self : Journal,
  record : @remote.DispatchRecord,
  key : String,
) -> Result[RecoveredSiteDispatch, NativeRemoteJournalIssue] {
  match self.database.read("site_managed_observation", key) {
    Ok(value) => {
      if value.revision != 0L ||
        !@remote.dispatch_record_requires_managed_observation(record) {
        return Err(StateCollision)
      }
      let body = @utf8.decode(value.body) catch {
        _ => return Err(Protocol(@remote.InvalidJournal))
      }
      let restored = match
        @remote.admit_remote_managed_output_observation_json(record, body) {
        Ok(item) => item
        Err(issue) => return Err(Protocol(issue))
      }
      let source_observation = match
        @remote.remote_managed_output_source_observation_json(record, body) {
        Ok(value) => value
        Err(issue) => return Err(Protocol(issue))
      }
      let file_custody = match
        self.restore_output_file(record, key, Some(restored.1)) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      Ok({
        record,
        file_custody,
        evidence: Some(restored.0),
        subject: Some(restored.1),
        measurement: Some(restored.2),
        source_observation,
      })
    }
    Err(@sqlite.NotFound) =>
      if @remote.dispatch_record_requires_managed_observation(record) {
        Err(StateCollision)
      } else {
        match self.restore_output_file(record, key, None) {
          Ok(None) => ()
          Ok(Some(_)) => return Err(StateCollision)
          Err(issue) => return Err(issue)
        }
        Ok({
          record,
          file_custody: None,
          evidence: None,
          subject: None,
          measurement: None,
          source_observation: None,
        })
      }
    Err(issue) => Err(Physical(issue))
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
      match self.begin_mutation(true) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      match self.database.read("site_dispatch", key) {
        Ok(value) => {
          ignore(self.database.rollback())
          return self.existing(request, value)
        }
        Err(@sqlite.NotFound) => ()
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
      match self.database.insert("site_dispatch", key, body) {
        Ok(0L) => ()
        Ok(_) | Err(@sqlite.Collision) => {
          ignore(self.database.rollback())
          return Err(StateCollision)
        }
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
      match self.database.commit() {
        Ok(_) => ()
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
      match @remote.commit_dispatch_acceptance(admission, true) {
        Ok(value) => Ok(value)
        Err(issue) => Err(Protocol(issue))
      }
    }
    Err(issue) => Err(Physical(issue))
  }
}

///|
/// Persist cancellation in this journal before any reply or physical stop.
/// Missing dispatch admission and the nonstartable tombstone are one fenced
/// transaction. Existing work retains its execution/evidence and cleanup;
/// only an unclaimed Accepted record may be confirmed cancelled here.
pub fn Journal::request_cancellation(
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
  let marker = match @remote.dispatch_request_json(request) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // This read and the exclusive start claim use the same transaction boundary.
  let existing = match self.database.read("site_dispatch", key) {
    Ok(value) => Some(value)
    Err(@sqlite.NotFound) => None
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  let admission = match existing {
    None =>
      match @remote.prepare_dispatch_cancellation(self.control, request) {
        Ok(value) => Some(value)
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Protocol(issue))
        }
      }
    Some(value) => {
      match self.existing(request, value) {
        Ok(_) => ()
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(issue)
        }
      }
      None
    }
  }
  let mut transition : @remote.DispatchTransition? = None
  let persist = fn() -> Result[Unit, NativeRemoteJournalIssue] {
    match self.database.read("site_cancel_request", key) {
      Ok(value) if value.revision == 0L && value.body == marker => ()
      Ok(_) => return Err(StateCollision)
      Err(@sqlite.NotFound) =>
        match self.database.insert("site_cancel_request", key, marker) {
          Ok(0L) => ()
          Ok(_) => return Err(StateCollision)
          Err(issue) => return Err(Physical(issue))
        }
      Err(issue) => return Err(Physical(issue))
    }
    match admission {
      Some(value) => {
        let body = match @remote.dispatch_admission_durable_json(value) {
          Ok(value) => @utf8.encode(value)
          Err(issue) => return Err(Protocol(issue))
        }
        let initial = match
          @remote.prepare_dispatch_acceptance(self.control, request) {
          Ok(value) => value
          Err(issue) => return Err(Protocol(issue))
        }
        let initial_body = match
          @remote.dispatch_admission_durable_json(initial) {
          Ok(value) => @utf8.encode(value)
          Err(issue) => return Err(Protocol(issue))
        }
        match self.database.insert("site_dispatch", key, initial_body) {
          Ok(0L) => ()
          Ok(_) => return Err(StateCollision)
          Err(issue) => return Err(Physical(issue))
        }
        match self.database.compare_exchange("site_dispatch", key, 0L, body) {
          Ok(1L) => ()
          Ok(_) => return Err(StateCollision)
          Err(issue) => return Err(Physical(issue))
        }
      }
      None => {
        let record = match self.require(request) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if @remote.dispatch_record_state_codes(record)[0] == 0 {
          match self.database.read("site_start_claim", key) {
            Ok(_) => return Err(StateCollision)
            Err(@sqlite.NotFound) => ()
            Err(issue) => return Err(Physical(issue))
          }
          let next = match @remote.prepare_confirm_execution_cancelled(record) {
            Ok(value) => value
            Err(issue) => return Err(Protocol(issue))
          }
          let body = match @remote.dispatch_transition_durable_json(next) {
            Ok(value) => @utf8.encode(value)
            Err(issue) => return Err(Protocol(issue))
          }
          let revision = @remote.dispatch_transition_expected_revision(next).to_int64()
          match
            self.database.compare_exchange("site_dispatch", key, revision, body) {
            Ok(value) if value == revision + 1L => transition = Some(next)
            Ok(_) => return Err(StateCollision)
            Err(issue) => return Err(Physical(issue))
          }
        }
      }
    }
    Ok(())
  }
  match persist() {
    Ok(_) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(issue)
    }
  }
  match self.database.commit() {
    Ok(_) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  // Memory commits follow physical durability, including uncertain-commit replay.
  match admission {
    Some(value) =>
      match @remote.commit_dispatch_acceptance(value, true) {
        Ok((_, record)) => return Ok(record)
        Err(issue) => return Err(Protocol(issue))
      }
    None => ()
  }
  match transition {
    Some(value) =>
      match @remote.commit_dispatch_transition(value, true) {
        Ok(_) => ()
        Err(issue) => return Err(Protocol(issue))
      }
    None => ()
  }
  self.require(request)
}

///|
/// Restore the exact saved cancellation intent; absence is not stop evidence.
pub fn Journal::cancellation_requested(
  self : Journal,
  request : @remote.DispatchRequest,
) -> Result[Bool, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let expected = match @remote.dispatch_request_json(request) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  match self.database.read("site_cancel_request", key) {
    Err(@sqlite.NotFound) => Ok(false)
    Err(issue) => Err(Physical(issue))
    Ok(value) if value.revision == 0L && value.body == expected => Ok(true)
    Ok(_) => Err(StateCollision)
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
    Err(@sqlite.NotFound) => return Err(MissingDispatch)
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
/// Restore one exact Site record and its typed evidence. Evidence bytes are
/// re-admitted by the portable protocol before they leave the physical
/// journal boundary.
pub fn Journal::observation(
  self : Journal,
  request : @remote.DispatchRequest,
) -> Result[RecoveredSiteDispatch, NativeRemoteJournalIssue] {
  let record = match self.require(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let key = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  self.restore_observation(record, key)
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
    Ok(record) =>
      match self.restore_observation(record, entry.key) {
        Ok(_) => Ok(Some((entry.key, record)))
        Err(issue) => Err(issue)
      }
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
      Ok(record) =>
        match self.restore_observation(record, entry.key) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
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
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.recover_all() {
    Ok(_) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(issue)
    }
  }
  let restart = match
    @remote.prepare_site_generation_restart(self.control, replacement) {
    Ok(value) => value
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Protocol(issue))
    }
  }
  let next_binding = match @remote.site_restart_next_binding_json(restart) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Protocol(issue))
    }
  }
  let metadata = match self.database.read("site_metadata", "binding") {
    Ok(value) => value
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  let mut physical_issue : NativeRemoteJournalIssue? = None
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
fn Journal::persist_transition(
  self : Journal,
  transition : @remote.DispatchTransition,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if @remote.dispatch_transition_installs_managed_observation(transition) {
    return Err(Protocol(@remote.InvalidTransition))
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
  match
    self.begin_mutation(
      @remote.dispatch_transition_requires_current_site(transition),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
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
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  if !durable {
    ignore(self.database.rollback())
    return Err(StateCollision)
  }
  match self.database.commit() {
    Ok(_) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  Ok(())
}

///|
fn valid_start_claimant(claimant : String) -> Bool {
  if claimant.is_empty() || claimant.length() > 128 {
    return false
  }
  for character in claimant {
    let code = character.to_int()
    if !((code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      code == 45 ||
      code == 46 ||
      code == 58 ||
      code == 95) {
      return false
    }
  }
  true
}

///|
fn start_claim_body(claimant : String, request_identity : String) -> String {
  "{\"claimant\":\"" +
  claimant +
  "\",\"dispatch_request_cid\":\"" +
  request_identity +
  "\",\"version\":\"actql-remote-start-claim/0.1\"}"
}

///|
fn start_claimant_of(body : Bytes) -> String {
  let text = @utf8.decode_lossy(body)
  let prefix = "{\"claimant\":\""
  guard text.has_prefix(prefix) else { return "" }
  let rest = text.unsafe_substring(start=prefix.length(), end=text.length())
  match rest.find("\"") {
    Some(end) => rest.unsafe_substring(start=0, end~)
    None => ""
  }
}

///|
/// Read the exact durable claimant without acquiring execution authority.
/// Recovery uses this identity to retire only the stopped holder's bundle
/// holding. A missing or corrupt claim cannot prove that holding absent.
pub fn Journal::start_claimant(
  self : Journal,
  request : @remote.DispatchRequest,
) -> Result[String?, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  match self.require(request) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match self.database.read("site_start_claim", key) {
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
    Ok(value) => {
      let claimant = start_claimant_of(value.body)
      if !valid_start_claimant(claimant) ||
        value.body !=
        @utf8.encode(
          start_claim_body(claimant, @remote.dispatch_request_identity(request)),
        ) {
        return Err(StateCollision)
      }
      Ok(Some(claimant))
    }
  }
}

///|
/// Exclusively claim the start of one dispatch attempt. The Accepted to
/// Provisioning transition and a start-claim record naming `claimant` are
/// written in one transaction fenced by the current Site binding. This is
/// distinct from `commit_transition`, whose idempotent retry of an identical
/// body would let two executors both succeed. A retried claim by the same
/// claimant after a lost reply is `AlreadyMine`; a claim by anyone else is
/// `LostTo`; a cancellation that won the Accepted state first is `Cancelled`.
pub fn Journal::claim_start(
  self : Journal,
  transition : @remote.DispatchTransition,
  claimant : String,
) -> Result[NativeRemoteStartClaim, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if !@remote.dispatch_transition_starts_execution(transition) ||
    !valid_start_claimant(claimant) {
    return Err(Protocol(@remote.InvalidTransition))
  }
  let key = match @remote.dispatch_transition_attempt_identity(transition) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let claim = @utf8.encode(
    start_claim_body(
      claimant,
      @remote.dispatch_transition_request_identity(transition),
    ),
  )
  let expected = @remote.dispatch_transition_expected_revision(transition)
  let next = match @remote.dispatch_transition_durable_json(transition) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.database.read("site_start_claim", key) {
    Ok(value) => {
      ignore(self.database.rollback())
      if value.body == claim {
        // The durable claim is ours; bring this process's view up to date
        // when the reply of the earlier claim was lost.
        ignore(@remote.commit_dispatch_transition(transition, true))
        return Ok(AlreadyMine)
      }
      return Ok(LostTo(start_claimant_of(value.body)))
    }
    Err(@sqlite.NotFound) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match
    self.database.compare_exchange(
      "site_dispatch",
      key,
      expected.to_int64(),
      next,
    ) {
    Ok(revision) if revision == expected.to_int64() + 1L => ()
    Ok(_) => {
      ignore(self.database.rollback())
      return Err(StateCollision)
    }
    Err(@sqlite.Collision) => {
      let current = match self.database.read("site_dispatch", key) {
        Ok(value) => value
        Err(issue) => {
          ignore(self.database.rollback())
          return Err(Physical(issue))
        }
      }
      ignore(self.database.rollback())
      return match @remote.admit_durable_dispatch_record(current.body) {
        Ok(record) =>
          if @remote.durable_dispatch_record_execution_cancelled(record) {
            Ok(Cancelled)
          } else {
            Ok(LostTo(""))
          }
        Err(issue) => Err(Protocol(issue))
      }
    }
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match self.database.insert("site_start_claim", key, claim) {
    Ok(0L) => ()
    Ok(_) | Err(@sqlite.Collision) => {
      ignore(self.database.rollback())
      return Err(StateCollision)
    }
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match self.database.commit() {
    Ok(_) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match @remote.commit_dispatch_transition(transition, true) {
    Ok(_) => Ok(Won)
    Err(issue) => Err(Protocol(issue))
  }
}

///|
/// Durably keep the exact dispatch envelope a resident Site admitted (the
/// dispatch request, its input binding and its run materials), keyed by the
/// attempt, before the dispatch is accepted. The executing process reads the
/// same bytes back; it never fetches them again. Keeping identical bytes again
/// is idempotent; different bytes for the same attempt are refused.
pub fn Journal::retain_dispatch_envelope(
  self : Journal,
  request : @remote.DispatchRequest,
  envelope : String,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let key = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let body = @utf8.encode(envelope)
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.database.read("site_dispatch_envelope", key) {
    Ok(value) => {
      ignore(self.database.rollback())
      return if value.body == body { Ok(()) } else { Err(StateCollision) }
    }
    Err(@sqlite.NotFound) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match self.database.insert("site_dispatch_envelope", key, body) {
    Ok(0L) => ()
    Ok(_) | Err(@sqlite.Collision) => {
      ignore(self.database.rollback())
      return Err(StateCollision)
    }
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match self.database.commit() {
    Ok(_) => Ok(())
    Err(issue) => {
      ignore(self.database.rollback())
      Err(Physical(issue))
    }
  }
}

///|
/// Durably keep one output intent before any payload can exist for it: `key`
/// names the exact payload request and `body` binds it to its dispatch
/// attempt. It is written under the current Site binding, so a holder of an
/// older generation cannot add one. Keeping identical bytes again is
/// idempotent; different bytes for the same key, or an intent that was
/// already completed, are refused, so a completed cleanup is never reopened.
pub fn Journal::retain_output_intent(
  self : Journal,
  key : String,
  body : String,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let bytes = @utf8.encode(body)
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.database.read("site_output_intent_done", key) {
    Ok(_) => {
      ignore(self.database.rollback())
      return Err(StateCollision)
    }
    Err(@sqlite.NotFound) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match self.database.read("site_output_intent", key) {
    Ok(value) => {
      ignore(self.database.rollback())
      return if value.body == bytes { Ok(()) } else { Err(StateCollision) }
    }
    Err(@sqlite.NotFound) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match self.database.insert("site_output_intent", key, bytes) {
    Ok(0L) => ()
    Ok(_) | Err(@sqlite.Collision) => {
      ignore(self.database.rollback())
      return Err(StateCollision)
    }
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match self.database.commit() {
    Ok(_) => Ok(())
    Err(issue) => {
      ignore(self.database.rollback())
      Err(Physical(issue))
    }
  }
}

///|
/// Output intents whose cleanup is not yet recorded complete, as `(key,
/// body)` pairs in key order.
pub fn Journal::pending_output_intents(
  self : Journal,
) -> Result[Array[(String, String)], NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let pending : Array[(String, String)] = []
  let mut cursor = ""
  while true {
    let entry = match self.database.scan_after("site_output_intent", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    cursor = entry.key
    match self.database.read("site_output_intent_done", entry.key) {
      Ok(_) => ()
      Err(@sqlite.NotFound) =>
        pending.push((entry.key, @utf8.decode_lossy(entry.body)))
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok(pending)
}

///|
/// Record that the cleanup of one output intent is confirmed. Only an
/// existing intent can be completed; completing it again is idempotent.
pub fn Journal::complete_output_intent(
  self : Journal,
  key : String,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  match self.begin_mutation(false) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.database.read("site_output_intent", key) {
    Ok(_) => ()
    Err(@sqlite.NotFound) => {
      ignore(self.database.rollback())
      return Err(MissingDispatch)
    }
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match self.database.read("site_output_intent_done", key) {
    Ok(_) => {
      ignore(self.database.rollback())
      return Ok(())
    }
    Err(@sqlite.NotFound) => ()
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match
    self.database.insert(
      "site_output_intent_done",
      key,
      @utf8.encode("{\"version\":\"actql-remote-output-intent-done/0.1\"}"),
    ) {
    Ok(0L) => ()
    Ok(_) | Err(@sqlite.Collision) => {
      ignore(self.database.rollback())
      return Err(StateCollision)
    }
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Physical(issue))
    }
  }
  match self.database.commit() {
    Ok(_) => Ok(())
    Err(issue) => {
      ignore(self.database.rollback())
      Err(Physical(issue))
    }
  }
}

///|
/// The dispatch envelope kept for one attempt identity, if any.
pub fn Journal::dispatch_envelope(
  self : Journal,
  attempt_identity : String,
) -> Result[String?, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  match self.database.read("site_dispatch_envelope", attempt_identity) {
    Ok(value) => Ok(Some(@utf8.decode_lossy(value.body)))
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn Journal::commit_transition(
  self : Journal,
  transition : @remote.DispatchTransition,
) -> Result[Unit, NativeRemoteJournalIssue] {
  match self.persist_transition(transition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match @remote.commit_dispatch_transition(transition, true) {
    Ok(_) => Ok(())
    Err(issue) => Err(Protocol(issue))
  }
}

///|
/// Durably transfers an exact unresolved responsibility into quarantine.
/// This ends normal Site authority without claiming physical reclamation.
pub fn Journal::force_loss(
  self : Journal,
  record : @remote.DispatchRecord,
  authorized : Bool,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let force = match
    @remote.prepare_force_loss(self.control, record, authorized) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match self.persist_transition(@remote.force_loss_transition(force)) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match @remote.commit_force_loss(force, true) {
    Ok(_) => Ok(())
    Err(issue) => Err(Protocol(issue))
  }
}

///|
/// Atomically store typed managed-output evidence with the Site transition
/// that makes it durable. A CID-only evidence transition is never accepted.
pub fn Journal::commit_evidence_transition(
  self : Journal,
  transition : @remote.DispatchTransition,
  evidence : @remote.RemoteExecutionEvidence,
  subject : @remote.RemoteManagedOutputSubject,
  measurement : @remote.RemoteManagedOutputMeasurement,
  source_observation? : @remote.RemoteSourceObservation? = None,
  file_custody? : NativeOutputFileCustody? = None,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if !@remote.dispatch_transition_installs_managed_observation(transition) {
    return Err(Protocol(@remote.InvalidTransition))
  }
  let key = match @remote.dispatch_transition_attempt_identity(transition) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let expected = @remote.dispatch_transition_expected_revision(transition)
  let dispatch_body = match
    @remote.dispatch_transition_durable_json(transition) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  let observation_body = match
    @remote.remote_managed_output_observation_json(
      transition,
      evidence,
      subject,
      measurement,
      source_observation~,
    ) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  let file_body = match file_custody {
    None => None
    Some(custody) => {
      if custody.request_cid !=
        @remote.dispatch_transition_request_identity(transition) ||
        !output_file_matches_subject(custody, subject) {
        return Err(StateCollision)
      }
      let body = match output_file_custody_json(custody) {
        Ok(value) => @utf8.encode(value)
        Err(issue) => return Err(issue)
      }
      if body.length().to_int64() > self.max_record_bytes {
        return Err(Physical(@sqlite.CapacityExceeded))
      }
      Some(body)
    }
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let mut failure : NativeRemoteJournalIssue? = None
  let mut already_committed = false
  match self.database.read("site_dispatch", key) {
    Ok(value) if value.revision == expected.to_int64() => ()
    Ok(value) if value.revision == expected.to_int64() + 1L &&
      value.body == dispatch_body => already_committed = true
    Ok(_) => failure = Some(StateCollision)
    Err(issue) => failure = Some(Physical(issue))
  }
  if failure is None {
    match self.database.read("site_managed_observation", key) {
      Ok(value) if already_committed &&
        value.revision == 0L &&
        value.body == observation_body => ()
      Ok(_) => failure = Some(StateCollision)
      Err(@sqlite.NotFound) if !already_committed =>
        match
          self.database.insert(
            "site_managed_observation", key, observation_body,
          ) {
          Ok(0L) => ()
          Ok(_) | Err(@sqlite.Collision) => failure = Some(StateCollision)
          Err(issue) => failure = Some(Physical(issue))
        }
      Err(@sqlite.NotFound) => failure = Some(StateCollision)
      Err(issue) => failure = Some(Physical(issue))
    }
  }
  if failure is None {
    match self.commit_output_file_snapshot(key, file_body, already_committed) {
      Ok(_) => ()
      Err(issue) => failure = Some(issue)
    }
  }
  if failure is None && !already_committed {
    match
      self.database.compare_exchange(
        "site_dispatch",
        key,
        expected.to_int64(),
        dispatch_body,
      ) {
      Ok(revision) if revision == expected.to_int64() + 1L => ()
      Ok(_) | Err(@sqlite.Collision) => failure = Some(StateCollision)
      Err(issue) => failure = Some(Physical(issue))
    }
  }
  match failure {
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
  let durable = if @remote.coordinator_dispatch_transition_is_replay(transition) {
    // The exact history is already durable. Read/admission above is the
    // replay linearization point; no CAS/revision write is performed.
    body == current_value.body
  } else {
    match
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
