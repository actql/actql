///|
pub(all) enum NativeRemoteJournalIssue {
  UnsupportedTarget
  Closed
  Physical(@sqlite.NativeSqliteIssue)
  Protocol(@remote.DispatchIssue)
  StateCollision
}

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
