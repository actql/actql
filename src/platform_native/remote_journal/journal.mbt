///|
pub(all) enum NativeRemoteJournalIssue {
  UnsupportedTarget
  Closed
  Physical(@sqlite.NativeSqliteIssue)
  Protocol(@remote.DispatchIssue)
  StaleSiteBinding
  MissingDispatch
  StateCollision
  InitializationCleanupPending(
    NativeRemoteJournalIssue?,
    NativeRemoteJournalIssue,
    CoordinatorInitializationCleanup
  )
}

///|
/// The outcome of an exclusive start claim for one dispatch attempt. Only
/// `Won` and `AlreadyMine` let the claimant begin execution; any other side
/// must not execute and reconciles the durable record instead.
pub(all) enum NativeRemoteStartClaim {
  /// This claimant just recorded the start.
  Won
  /// This claimant's start was already durable, for example after a lost
  /// reply. The record may need to be read again.
  AlreadyMine
  /// Another claimant (or a start without a claim, as the empty name)
  /// began this attempt.
  LostTo(String)
  /// Cancellation won the same Accepted state first.
  Cancelled
} derive(Eq, Debug)

///|
#warnings("-struct_never_constructed")
struct RecoveredCoordinatorDispatch {
  key : String
  record : @remote.CoordinatorDispatchIntentRecord
  evidence : @remote.RemoteExecutionEvidence?
  subject : @remote.RemoteManagedOutputSubject?
  measurement : @remote.RemoteManagedOutputMeasurement?
}

///|
/// One exact durable Site record and its typed managed-output observation.
/// The three optional values are either all present or all absent.
///
#warnings("-struct_never_constructed")
struct RecoveredSiteDispatch {
  record : @remote.DispatchRecord
  evidence : @remote.RemoteExecutionEvidence?
  subject : @remote.RemoteManagedOutputSubject?
  measurement : @remote.RemoteManagedOutputMeasurement?
}

///|
pub fn recovered_site_dispatch_record(
  recovered : RecoveredSiteDispatch,
) -> @remote.DispatchRecord {
  recovered.record
}

///|
pub fn recovered_site_dispatch_evidence(
  recovered : RecoveredSiteDispatch,
) -> @remote.RemoteExecutionEvidence? {
  recovered.evidence
}

///|
pub fn recovered_site_dispatch_subject(
  recovered : RecoveredSiteDispatch,
) -> @remote.RemoteManagedOutputSubject? {
  recovered.subject
}

///|
pub fn recovered_site_dispatch_measurement(
  recovered : RecoveredSiteDispatch,
) -> @remote.RemoteManagedOutputMeasurement? {
  recovered.measurement
}

///|
pub fn recovered_coordinator_dispatch_key(
  recovered : RecoveredCoordinatorDispatch,
) -> String {
  recovered.key
}

///|
pub fn recovered_coordinator_dispatch_record(
  recovered : RecoveredCoordinatorDispatch,
) -> @remote.CoordinatorDispatchIntentRecord {
  recovered.record
}

///|
pub fn recovered_coordinator_dispatch_evidence(
  recovered : RecoveredCoordinatorDispatch,
) -> @remote.RemoteExecutionEvidence? {
  recovered.evidence
}

///|
pub fn recovered_coordinator_dispatch_subject(
  recovered : RecoveredCoordinatorDispatch,
) -> @remote.RemoteManagedOutputSubject? {
  recovered.subject
}

///|
pub fn recovered_coordinator_dispatch_measurement(
  recovered : RecoveredCoordinatorDispatch,
) -> @remote.RemoteManagedOutputMeasurement? {
  recovered.measurement
}
