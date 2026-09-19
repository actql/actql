///|
type Journal

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
#warnings("-unused_value")
fn retain_native_import() -> Unit {
  ignore(@utf8.decode_lossy(b""))
}
