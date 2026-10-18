///|
/// Private installed caller's physical binding check only. Each actual Root
/// must retain the same currently entered original Read context. Neither an
/// equal path/ownership projection nor legacy allocation supplies that origin.
/// Callers must independently preserve the complete original Host/adoption,
/// account/current and SQLite fences before protected work.
pub fn NativeLocalAdoptionSession::require_current_original_read_roots(
  self : NativeLocalAdoptionSession,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closed || self.close_pending {
    return Err(Closed)
  }
  match self.source_root.require_current_original_read() {
    Err(issue) => return Err(Filesystem(issue))
    Ok(_) => ()
  }
  match self.parent.require_current_original_read() {
    Err(issue) => return Err(Filesystem(issue))
    Ok(_) => ()
  }
  match self.root.require_current_original_read() {
    Err(issue) => return Err(Filesystem(issue))
    Ok(_) => ()
  }
  if self.settings.managed is Some(managed) {
    match managed.root.require_current_original_read() {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => ()
    }
  }
  Ok(())
}
