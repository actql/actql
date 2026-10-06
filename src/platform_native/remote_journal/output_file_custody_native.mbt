///|
/// Only called inside the existing managed-evidence transaction. A duplicate
/// commit must reproduce the same custody, including the absence of custody.
fn Journal::commit_output_file_snapshot(
  self : Journal,
  key : String,
  body : Bytes?,
  already_committed : Bool,
) -> Result[Unit, NativeRemoteJournalIssue] {
  match (self.database.read("site_output_file", key), body) {
    (Ok(value), Some(expected)) if already_committed &&
      value.revision == 0L &&
      value.body == expected => Ok(())
    (Err(@sqlite.NotFound), None) => Ok(())
    (Err(@sqlite.NotFound), Some(body)) if !already_committed =>
      match self.database.insert("site_output_file", key, body) {
        Ok(0L) => Ok(())
        Ok(_) | Err(@sqlite.Collision) => Err(StateCollision)
        Err(issue) => Err(Physical(issue))
      }
    (Err(@sqlite.NotFound), _) => Err(StateCollision)
    (Err(issue), _) => Err(Physical(issue))
    _ => Err(StateCollision)
  }
}

///|
fn Journal::restore_output_file(
  self : Journal,
  record : @remote.DispatchRecord,
  key : String,
  subject : @remote.RemoteManagedOutputSubject?,
) -> Result[NativeOutputFileCustody?, NativeRemoteJournalIssue] {
  match self.database.read("site_output_file", key) {
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
    Ok(value) => {
      if value.revision != 0L {
        return Err(StateCollision)
      }
      guard subject is Some(subject) else { return Err(StateCollision) }
      let body = @utf8.decode(value.body) catch {
        _ => return Err(StateCollision)
      }
      let custody = match
        admit_output_file_custody(@remote.dispatch_record_request(record), body) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !output_file_matches_subject(custody, subject) {
        return Err(StateCollision)
      }
      Ok(Some(custody))
    }
  }
}
