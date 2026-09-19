///|
type Journal

///|
type CoordinatorJournal

///|
pub fn open_journal(
  _library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  control : @remote.SiteDispatchJournal,
) -> Result[Journal, NativeRemoteJournalIssue] {
  ignore(path)
  ignore(max_record_bytes)
  ignore(control)
  Err(UnsupportedTarget)
}

///|
pub fn open_coordinator_journal(
  _library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  control : @remote.CoordinatorDispatchJournal,
) -> Result[CoordinatorJournal, NativeRemoteJournalIssue] {
  ignore(path)
  ignore(max_record_bytes)
  ignore(control)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::accept(
  _self : Journal,
  request : @remote.DispatchRequest,
) -> Result[
  (@remote.DispatchAcceptance, @remote.DispatchRecord),
  NativeRemoteJournalIssue,
] {
  ignore(request)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::recover_after(
  _self : Journal,
  after_key : String,
) -> Result[(String, @remote.DispatchRecord)?, NativeRemoteJournalIssue] {
  ignore(after_key)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::commit_transition(
  _self : Journal,
  transition : @remote.DispatchTransition,
) -> Result[Unit, NativeRemoteJournalIssue] {
  ignore(transition)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::close(_self : Journal) -> Bool {
  false
}

///|
pub fn CoordinatorJournal::accept(
  _self : CoordinatorJournal,
  request : @remote.DispatchRequest,
) -> Result[
  (@remote.DispatchAcceptance, @remote.CoordinatorDispatchIntentRecord),
  NativeRemoteJournalIssue,
] {
  ignore(request)
  Err(UnsupportedTarget)
}

///|
pub fn CoordinatorJournal::commit_transition(
  _self : CoordinatorJournal,
  transition : @remote.CoordinatorDispatchTransition,
  evidence? : @remote.RemoteExecutionEvidence? = None,
  subject? : @remote.RemoteManagedOutputSubject? = None,
  measurement? : @remote.RemoteManagedOutputMeasurement? = None,
) -> Result[Unit, NativeRemoteJournalIssue] {
  ignore(transition)
  ignore(evidence)
  ignore(subject)
  ignore(measurement)
  Err(UnsupportedTarget)
}

///|
pub fn CoordinatorJournal::recover_after(
  _self : CoordinatorJournal,
  after_key : String,
) -> Result[RecoveredCoordinatorDispatch?, NativeRemoteJournalIssue] {
  ignore(after_key)
  Err(UnsupportedTarget)
}

///|
pub fn CoordinatorJournal::close(_self : CoordinatorJournal) -> Bool {
  false
}

///|
#warnings("-unused_value")
fn retain_native_import() -> Unit {
  ignore(@utf8.decode_lossy(b""))
}
