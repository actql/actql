///|
pub(all) enum NativeRemoteJournalIssue {
  UnsupportedTarget
  Closed
  Physical(@sqlite.NativeSqliteIssue)
  Protocol(@remote.DispatchIssue)
  StateCollision
}
