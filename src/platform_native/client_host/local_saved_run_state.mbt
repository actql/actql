///|
/// Saved original outcome only. The SQL Submission metadata revision is never
/// exposed as a public control revision. Control remains the actual Run row.
struct NativeClientSavedRunState {
  original : @host.ClientRunStateOriginal
  control_revision : Int64
}

///|
pub fn NativeClientSavedRunState::wire(
  self : NativeClientSavedRunState,
) -> String {
  self.original.state_wire()
}

///|
pub fn NativeClientSavedRunState::control_revision(
  self : NativeClientSavedRunState,
) -> Int64 {
  self.control_revision
}

///|
pub(all) enum NativeClientSavedRunStateIssue {
  Unavailable
  Journal(NativeClientRunJournalIssue)
}

///|
fn NativeClientRunJournal::saved_run_state_locked(
  self : NativeClientRunJournal,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
) -> Result[
  (NativeClientSubmittedIntentRecord, NativeClientRunRecord),
  NativeClientRunJournalIssue,
] {
  match self.submitted_intent_custody() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let original = match self.retained_submission(reference) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  guard original.run_admission is Some(admission) else {
    return Err(CustodyLost)
  }
  if @host.client_request_identity_relation(admission.request, request) !=
    @host.SameRequest {
    return Err(ChangedIntent)
  }
  let run = match self.retained(request) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  if @publication.publication_contract_identity(run.definition) !=
    admission.run_definition_cid {
    return Err(ForeignRun)
  }
  Ok((original, run))
}

///|
fn NativeClientRunJournal::retain_observed_run_state(
  self : NativeClientRunJournal,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  observed : @native_publication.NativeObservedRunState,
  store : @publication_store.Store,
  namespace_id : String,
  authority : NativeLocalPolicyAuthority,
) -> Result[NativeClientSavedRunState, NativeClientRunJournalIssue] {
  self.transaction(() => {
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    let (original, run) = match
      self.saved_run_state_locked(reference, request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    // Legacy admission cannot be repaired with a later observation.
    if run.run_observation_originals is None {
      return Err(CustodyLost)
    }
    let definition = @publication.publication_contract_identity(run.definition)
    if !observed.matches_original_store(
        store,
        namespace_id,
        authority.scope,
        definition,
      ) {
      return Err(ForeignRun)
    }
    let publication = match
      install_native_client_cancellation_publication(
        store, namespace_id, 65536, 8192, 64,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if run.publication_binding != publication.binding {
      return Err(ForeignRun)
    }
    let wire = observed.original_wire()
    let state = match
      @host.restore_client_run_state_original(run.definition, wire) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    let body = match
      submitted_intent_body(
        original.reference,
        original.intent,
        run_admission=original.run_admission,
        run_state_original=Some(wire),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    match original.run_state_original {
      Some(prior) if prior == wire => ()
      Some(_) => return Err(ChangedIntent)
      None =>
        match
          self.database.compare_exchange(
            "client_submitted_intents",
            reference.request_id,
            original.revision,
            body,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Physical(issue))
        }
    }
    // A metadata CAS never calls save(run), changes accepted revision, or
    // creates a second control CAS. Current is checked before commit as well.
    if !authority.current_for(self, request) {
      return Err(AuthorizationDenied)
    }
    let current_publication = match
      install_native_client_cancellation_publication(
        store, namespace_id, 65536, 8192, 64,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if current_publication.binding != publication.binding {
      return Err(CustodyLost)
    }
    Ok({ original: state, control_revision: run.revision, })
  })
}

///|
/// Save only the original actual-Store opaque observation, under current
/// adopted RunRead. Old compiler Allow is metadata, never current permission.
pub fn NativeLocalHostConnection::retain_submitted_run_state(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  observed : @native_publication.NativeObservedRunState,
  store : @publication_store.Store,
  namespace_id : String,
  now : Double,
) -> Result[NativeClientSavedRunState, NativeClientRunJournalIssue] {
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      ReadRunMaterials,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    self.journal.lookup_submitted_intent(
      self.epoch,
      reference,
      authority.scope,
      authority.current_for(self.journal, request),
      now,
    ) {
    Ok(Submitted(_)) => ()
    Ok(UnresolvedSubmissionHistory) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  self.journal.retain_observed_run_state(
    reference, request, observed, store, namespace_id, authority,
  )
}

///|
/// Restore exact saved bytes without Store open, publication, preparation or
/// execution. Missing legacy state remains Unavailable; current is independent.
pub fn NativeLocalHostConnection::lookup_submitted_run_state(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
) -> Result[NativeClientSavedRunState, NativeClientSavedRunStateIssue] {
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      ReadRunMaterials,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  match
    self.journal.lookup_submitted_intent(
      self.epoch,
      reference,
      authority.scope,
      authority.current_for(self.journal, request),
      now,
    ) {
    Ok(Submitted(value)) if value.run_admission is Some(_) => ()
    Ok(_) => return Err(Unavailable)
    Err(issue) => return Err(Journal(issue))
  }
  self.journal
  .transaction(() => {
    if !authority.current_for(self.journal, request) {
      return Err(AuthorizationDenied)
    }
    let read : Result[NativeClientSavedRunState?, NativeClientRunJournalIssue] = match
      self.journal.saved_run_state_locked(reference, request) {
      Ok((original, run)) =>
        match original.run_state_original {
          None => Ok(None)
          Some(wire) =>
            @host.restore_client_run_state_original(run.definition, wire)
            .map(value => {
              Some({ original: value, control_revision: run.revision, })
            })
            .map_err(_ => CustodyLost)
        }
      Err(issue) => Err(issue)
    }
    if !authority.current_for(self.journal, request) {
      return Err(AuthorizationDenied)
    }
    read
  })
  .map_err(issue => NativeClientSavedRunStateIssue::Journal(issue))
  .bind(value => {
    match value {
      Some(value) => Ok(value)
      None => Err(Unavailable)
    }
  })
}
