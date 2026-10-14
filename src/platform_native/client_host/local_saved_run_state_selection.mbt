///|
/// Original identity and saved observation, not a grant or a new Run. The
/// definition/reference come only from the authenticated retained journal.
struct NativeClientSavedRunStateSelection {
  reference : NativeClientSubmissionReference
  definition : @publication.PublicationContract
  state : NativeClientSavedRunState
}

///|
pub fn NativeClientSavedRunStateSelection::reference(
  self : NativeClientSavedRunStateSelection,
) -> NativeClientSubmissionReference {
  self.reference
}

///|
pub fn NativeClientSavedRunStateSelection::definition(
  self : NativeClientSavedRunStateSelection,
) -> @publication.PublicationContract {
  self.definition
}

///|
pub fn NativeClientSavedRunStateSelection::state(
  self : NativeClientSavedRunStateSelection,
) -> NativeClientSavedRunState {
  self.state
}

///|
// The argument is a selector only. Check this concrete Host's current adopted
// scope and run/read before and after the bounded, full-custody identity scan.
fn saved_run_selection_current(
  host : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  scope : String,
) -> Bool {
  host.authority_scope_cid(principal, connection, crypto) is Ok(current) &&
  current == scope &&
  host.authorize({ principal, connection, resource: "run", operation: "read", })
  is Ok(@authorization.Allow(_))
}

///|
/// Select one existing Run by its original ID, then use the same authenticated
/// Submission/state reader. No incoming ID is converted into an admission or
/// reference. Ambiguous IDs refuse; missing legacy state remains Unavailable.
pub fn NativeLocalHostConnection::lookup_submitted_run_state_by_id(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  run_id : String,
  now : Double,
) -> Result[NativeClientSavedRunStateSelection, NativeClientSavedRunStateIssue] {
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(_) => return Err(Journal(AuthorizationDenied))
  }
  let current = () => {
    saved_run_selection_current(self, crypto, principal, connection, scope)
  }
  if !current() {
    return Err(Journal(AuthorizationDenied))
  }
  let selected = match
    self.journal.transaction(() => {
      if !current() {
        return Err(AuthorizationDenied)
      }
      let selected = self.journal.select_saved_state_run_id_locked(
        scope, run_id,
      )
      if !current() {
        return Err(AuthorizationDenied)
      }
      selected
    }) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Unavailable)
    Err(issue) => return Err(Journal(issue))
  }
  let (reference, request, definition) = selected
  let state = match
    self.lookup_submitted_run_state(
      crypto, principal, connection, reference, request, now,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !current() {
    return Err(Journal(AuthorizationDenied))
  }
  Ok({ reference, definition, state, })
}

///|
// Shared journal readers validate every row/body/Run join. Keep only one
// original selection, with no authority or caller-provided scan callback.
fn NativeClientRunJournal::select_saved_state_run_id_locked(
  self : NativeClientRunJournal,
  scope : String,
  run_id : String,
) -> Result[
  (
    NativeClientSubmissionReference,
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
  )?,
  NativeClientRunJournalIssue,
] {
  match self.submitted_intent_custody() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let mut selected : (
    NativeClientSubmissionReference,
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
  )? = None
  let mut cursor = ""
  let mut count = 0
  while true {
    let row = match
      self.database.scan_after("client_submitted_intents", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    if row.key <= cursor || count >= self.max_records {
      return Err(CustodyLost)
    }
    cursor = row.key
    count = count + 1
    let original = match
      self.inspect_submitted_intent_row({
        key: row.key,
        revision: row.revision,
        body: row.body,
      }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard original.run_admission is Some((request, _, _)) else { continue }
    if @host.client_request_authority_scope_cid(request) != scope {
      continue
    }
    let run = match self.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    let original_id = match @publication.run_definition_run_id(run.definition) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    if original_id == run_id {
      if selected is Some(_) {
        return Err(ForeignRun)
      }
      selected = Some(
        (
          native_submission_reference_record(original.reference),
          request,
          run.definition,
        ),
      )
    }
  }
  Ok(selected)
}
