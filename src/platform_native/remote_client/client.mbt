///|
pub(all) enum NativeRemoteClientIssue {
  UnsupportedTarget
  Closed
  Http(@http.NativeHttpIssue)
  Journal(@journal.NativeRemoteJournalIssue)
  Protocol(@remote.DispatchIssue)
  HttpStatus(Int)
  InvalidUtf8
  OutcomeUnknownPersistence(
    @journal.NativeRemoteJournalIssue,
    NativeRemoteClientIssue
  )
}
