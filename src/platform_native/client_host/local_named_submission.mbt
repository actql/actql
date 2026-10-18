///|
// Same adopted Host scope and actual Account tuple. The final checks below are
// non-callback lifetime/identity predicates, not another permission evaluator.
fn named_submission_current(
  host : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  scope : String,
) -> Bool {
  host.authority_scope_cid(principal, connection, crypto) is Ok(current) &&
  current == scope &&
  host.authorize({
    principal,
    connection,
    resource: "run",
    operation: "submit",
  })
  is Ok(@authorization.Allow(_)) &&
  !host.closed &&
  !host.database_closed &&
  !host.session_closed &&
  !host.session.closed &&
  physical_equal(host.database, host.journal.database) &&
  physical_equal(host.database, host.epoch.database)
}

///|
/// Trusted Local submission entry. Namespace is the installed Local namespace;
/// actor comes from the authenticated principal, never the incoming name DATA.
/// A candidate is authenticated only after this same Journal confirms absence.
/// Retained/preparing observations never authorize preparation or continuation.
pub fn NativeLocalHostConnection::resolve_or_bind_submitted_name(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  name : String,
  intent : @host.ClientSubmittedIntent,
  candidate : NativeClientSubmissionReference?,
  now : Double,
) -> Result[NativeClientNamedSubmissionLookup, NativeClientRunJournalIssue] {
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(_) => return Err(AuthorizationDenied)
  }
  let current = () => {
    named_submission_current(self, crypto, principal, connection, scope)
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  let (key, index) = match
    native_client_submitted_name_index("local", principal, name, scope) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Preserve the Epoch Owner's independent monotonic watermark COMMIT.
  match self.epoch.clock(now) {
    Ok(_) => ()
    Err(issue) => return Err(Epoch(issue))
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  let selected = match
    self.journal.transaction(() => {
      if !current() {
        return Err(AuthorizationDenied)
      }
      let selected = match
        self.journal.resolve_submitted_name_locked(
          self.epoch,
          key,
          index,
          intent,
          candidate,
          scope,
          true,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !current() {
        return Err(AuthorizationDenied)
      }
      Ok(selected)
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue) // COMMIT Unknown is not an absent name.
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  Ok(selected)
}
