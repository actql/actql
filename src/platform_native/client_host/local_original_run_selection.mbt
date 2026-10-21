///|
/// Authenticated original identity only. This selection is not a saved state,
/// permission, Result grant or authority to prepare, dispatch or replay a Run.
struct NativeClientOriginalRunSelection {
  reference : NativeClientSubmissionReference
  request : @host.ClientRequestIdentity
  definition : @publication.PublicationContract
  scope : String
}

///|
pub fn NativeClientOriginalRunSelection::reference(
  self : NativeClientOriginalRunSelection,
) -> NativeClientSubmissionReference {
  self.reference
}

///|
pub fn NativeClientOriginalRunSelection::request(
  self : NativeClientOriginalRunSelection,
) -> @host.ClientRequestIdentity {
  self.request
}

///|
pub fn NativeClientOriginalRunSelection::definition(
  self : NativeClientOriginalRunSelection,
) -> @publication.PublicationContract {
  self.definition
}

///|
// The same original scan used by status, at the same transaction/current
// boundaries. Status separately requires its saved observation; an identity
// read must not fabricate one for a legacy or not-yet-observed Run.
fn NativeLocalHostConnection::select_original_run_id(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  run_id : String,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[NativeClientOriginalRunSelection, NativeClientSavedRunStateIssue] {
  let reads = operations.map(value => value.reads)
  let scope_result = match capture {
    None => self.authority_scope_cid(principal, connection, crypto)
    Some(original) => {
      guard original.opening is JournalAcquired(host) &&
        physical_equal(host, self) else {
        return Err(Journal(AuthorizationDenied))
      }
      original.authority_scope_cid_in_original_read(principal, connection)
    }
  }
  let scope = match scope_result {
    Ok(value) => value
    Err(_) => return Err(Journal(AuthorizationDenied))
  }
  let current = () => {
    saved_run_selection_current(
      self,
      crypto,
      principal,
      connection,
      scope,
      capture~,
    )
  }
  if !current() {
    return Err(Journal(AuthorizationDenied))
  }
  let selected = match
    self.journal.transaction_with_reads(
      () => {
        if !current() {
          return Err(AuthorizationDenied)
        }
        let selected = self.journal.select_saved_state_run_id_locked(
          self.epoch,
          scope,
          run_id,
          reads~,
        )
        if !current() {
          return Err(AuthorizationDenied)
        }
        selected
      },
      reads~,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Unavailable)
    Err(issue) => return Err(Journal(issue))
  }
  let (reference, request, definition) = selected
  Ok({ reference, request, definition, scope, })
}

///|
/// Read one retained original Run selected by ID through this real adopted
/// Host's current RunRead. Callers still need their own current operation and
/// Result policy admission. No caller reference, state wire or current project
/// file repairs a missing original. The locator validates its exact retained original.
pub fn NativeLocalHostConnection::lookup_submitted_run_original_by_id(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  run_id : String,
) -> Result[NativeClientOriginalRunSelection, NativeClientSavedRunStateIssue] {
  self.lookup_submitted_run_original_by_id_with_operations(
    crypto, principal, connection, run_id,
  )
}

///|
fn NativeLocalHostConnection::lookup_submitted_run_original_by_id_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  run_id : String,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[NativeClientOriginalRunSelection, NativeClientSavedRunStateIssue] {
  let selected = match
    self.select_original_run_id(
      crypto,
      principal,
      connection,
      run_id,
      operations~,
      capture~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !saved_run_selection_current(
      self,
      crypto,
      principal,
      connection,
      selected.scope,
      capture~,
    ) {
    return Err(Journal(AuthorizationDenied))
  }
  Ok(selected)
}
