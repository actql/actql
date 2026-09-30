///|
type Journal

///|
type CoordinatorJournal

///|
type CoordinatorInitializationCleanup

///|
pub fn CoordinatorInitializationCleanup::pending(
  _self : CoordinatorInitializationCleanup,
) -> Bool {
  false
}

///|
pub fn CoordinatorInitializationCleanup::retry(
  _self : CoordinatorInitializationCleanup,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

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
pub fn Journal::require(
  _self : Journal,
  request : @remote.DispatchRequest,
) -> Result[@remote.DispatchRecord, NativeRemoteJournalIssue] {
  ignore(request)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::observation(
  _self : Journal,
  _request : @remote.DispatchRequest,
) -> Result[RecoveredSiteDispatch, NativeRemoteJournalIssue] {
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
pub fn Journal::restart(
  _self : Journal,
  replacement : @site.ExecutionSite,
) -> Result[Int, NativeRemoteJournalIssue] {
  ignore(replacement)
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
pub fn Journal::force_loss(
  _self : Journal,
  record : @remote.DispatchRecord,
  authorized : Bool,
) -> Result[Unit, NativeRemoteJournalIssue] {
  ignore(record)
  ignore(authorized)
  Err(UnsupportedTarget)
}

///|
pub fn Journal::commit_evidence_transition(
  _self : Journal,
  transition : @remote.DispatchTransition,
  evidence : @remote.RemoteExecutionEvidence,
  subject : @remote.RemoteManagedOutputSubject,
  measurement : @remote.RemoteManagedOutputMeasurement,
) -> Result[Unit, NativeRemoteJournalIssue] {
  ignore(transition)
  ignore(evidence)
  ignore(subject)
  ignore(measurement)
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
pub fn CoordinatorJournal::require(
  _self : CoordinatorJournal,
  _request : @remote.DispatchRequest,
) -> Result[@remote.CoordinatorDispatchIntentRecord, NativeRemoteJournalIssue] {
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

///|
pub fn Journal::claim_start(
  _self : Journal,
  _transition : @remote.DispatchTransition,
  _claimant : String,
) -> Result[NativeRemoteStartClaim, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::retain_dispatch_envelope(
  _self : Journal,
  _request : @remote.DispatchRequest,
  _envelope : String,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::dispatch_envelope(
  _self : Journal,
  _attempt_identity : String,
) -> Result[String?, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::retain_output_intent(
  _self : Journal,
  _key : String,
  _body : String,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::pending_output_intents(
  _self : Journal,
) -> Result[Array[(String, String)], NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::complete_output_intent(
  _self : Journal,
  _key : String,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}
