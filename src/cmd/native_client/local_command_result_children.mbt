///|
// The original Result/Store methods enter and return their own Read/SQL
// scopes. Do not wrap the whole close in another Store/SQL flight. The parent
// has already reconciled the same pending return before reaching this method.
fn LocalCommandBusinessOriginal::close_result_children(
  self : LocalCommandBusinessOriginal,
) -> Result[Unit, LocalCommandPreparationIssue] {
  if self.result_sink is Some(sink) {
    match sink.close() {
      Err(issue) => {
        if self.result_cleanup_issue is None {
          self.result_cleanup_issue = Some(issue)
        }
        return Err(CommandBusinessResult(issue))
      }
      Ok(_) => ()
    }
  }
  // A sink may never have been installed. The exact acquired session remains
  // separately retained; a sink error never substitutes for its close ACK.
  if self.result_session is Some(session) {
    match session.close() {
      Err(issue) => {
        if self.result_cleanup_issue is None {
          self.result_cleanup_issue = Some(issue)
        }
        return Err(CommandBusinessResult(issue))
      }
      Ok(_) => ()
    }
  }
  // Both Result close entrances return only after the original Store return.
  // Keep even closed aliases until that acknowledgement; no poll/receipt or
  // payload reopen is performed by this cleanup path.
  self.result_sink = None
  self.result_session = None
  self.result_service = None
  self.result_binding = None
  self.result_refusal = None
  // The outer command retains its primary presentation. Retire this last
  // Read-managed diagnostic only after the same session/Store return ACKs,
  // before the parent can retire the actual Read domain.
  self.result_cleanup_issue = None
  Ok(())
}
