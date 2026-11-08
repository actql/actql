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
// Original issuer metadata plus the actual counter from the same retained row.
// Preparation is not current authority or a COMMIT acknowledgement.
fn native_saved_state_observation(
  run : NativeClientRunRecord,
  state : @host.ClientRunStateOriginal,
  revision : Int64,
) -> Result[@publication.RunStateObservation, NativeClientRunJournalIssue] {
  let run_id = match @publication.run_definition_run_id(run.definition) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  @publication.prepare_run_state_observation(
    state.state_wire(),
    run_id,
    revision,
    65536,
    8192,
    64,
  ).map_err(_ => CustodyLost)
}

///|
fn NativeClientRunJournal::saved_run_state_locked(
  self : NativeClientRunJournal,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[
  (NativeClientSubmittedIntentRecord, NativeClientRunRecord),
  NativeClientRunJournalIssue,
] {
  match
    client_journal_issuance_anchor(
      self.database,
      "client_submitted_intent_custody",
      self.max_records,
      reads~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (original, selected_run) = match
    self.retained_submission_with_run(reference, reads~) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  guard original.run_admission is Some(admission) && selected_run is Some(run) else {
    return Err(CustodyLost)
  }
  if @host.client_request_identity_relation(admission.request, request) !=
    @host.SameRequest {
    return Err(ChangedIntent)
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
  observed : NativeLocalObservedRunState,
  authority : NativeLocalPolicyAuthority,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientSavedRunState, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  self.transaction_with_reads(
    () => {
      if !authority.current_for(self, request) ||
        !observed.publisher.current_in_owned_transaction() {
        return Err(AuthorizationDenied)
      }
      let (original, run) = match
        self.saved_run_state_locked(reference, request, reads~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      // Legacy admission cannot be repaired with a later observation.
      if run.run_observation_originals is None {
        return Err(CustodyLost)
      }
      let definition = @publication.publication_contract_identity(
        run.definition,
      )
      if observed.definition_cid() != definition ||
        @host.client_request_identity_relation(observed.request, request) !=
        @host.SameRequest ||
        !physical_equal(observed.host, authority.host) {
        return Err(ForeignRun)
      }
      let store = observed.publisher.store
      let namespace_id = observed.publisher.namespace_id
      if !observed.publisher.current_in_owned_transaction() {
        return Err(AuthorizationDenied)
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
      guard original.run_state_observation is Some((prior_revision, prior_key)) else {
        // Historical absence is not the original issuance of counter zero.
        return Err(CustodyLost)
      }
      let run_id = match @publication.run_definition_run_id(run.definition) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let observation = match
        @publication.prepare_run_state_observation(
          observed.wire(),
          run_id,
          prior_revision,
          65536,
          8192,
          64,
        ) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let revision = match
        observation.next_revision(prior_key, prior_revision) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let state_wire = match observation.wire(revision) {
        Ok(value) => value
        Err(_) => return Err(CapacityExceeded)
      }
      let state = match
        @host.prepare_client_run_state_original(
          run.definition,
          observed.original_manifest(),
          state_wire,
        ) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let wire = state.wire()
      let body = match
        submitted_intent_body(
          before_construction=submitted_encode_construction(
            self.database,
            operations,
          ),
          original.reference,
          original.intent,
          run_admission=original.run_admission,
          run_state_original=Some(wire),
          run_state_observation=Some((revision, Some(observation.key()))),
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !authority.current_for(self, request) ||
        !observed.publisher.current_in_owned_transaction() {
        return Err(AuthorizationDenied)
      }
      match original.run_state_original {
        Some(prior) if prior == wire => ()
        _ => {
          self.invalidate_operation_submission()
          match
            compare_exchange_client_journal_value(
              self.database,
              "client_submitted_intents",
              reference.request_id,
              original.revision,
              body,
              operations,
            ) {
            Ok(_) => ()
            Err(issue) => return Err(Physical(issue))
          }
        }
      }
      // A metadata CAS never calls save(run), changes accepted revision, or
      // creates a second control CAS. Current is checked before commit as well.
      if !authority.current_for(self, request) ||
        !observed.publisher.current_in_owned_transaction() {
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
    },
    reads~,
  )
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
  observed : NativeLocalObservedRunState,
  now : Double,
) -> Result[NativeClientSavedRunState, NativeClientRunJournalIssue] {
  self.retain_submitted_run_state_with_operations(
    crypto, principal, connection, reference, request, observed, now,
  )
}

///|
fn NativeLocalHostConnection::retain_submitted_run_state_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  observed : NativeLocalObservedRunState,
  now : Double,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[NativeClientSavedRunState, NativeClientRunJournalIssue] {
  if !physical_equal(observed.host, self) ||
    @host.client_request_identity_relation(observed.request, request) !=
    @host.SameRequest {
    return Err(ForeignRun)
  }
  if observed.read_authority.principal != principal ||
    observed.read_authority.connection != connection ||
    !observed.require_current_for(self, request) {
    return Err(AuthorizationDenied)
  }
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      ReadRunMaterials,
      capture~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    self.journal.lookup_submitted_intent_with_operations(
      self.epoch,
      reference,
      authority.scope,
      authority.current_for(self.journal, request),
      now,
      operations~,
    ) {
    Ok(Submitted(_)) => ()
    Ok(UnresolvedSubmissionHistory) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  self.journal.retain_observed_run_state(
    reference,
    request,
    observed,
    authority,
    operations~,
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
  self.lookup_submitted_run_state_with_operations(
    crypto, principal, connection, reference, request, now,
  )
}

///|
fn NativeLocalHostConnection::lookup_submitted_run_state_with_operations(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[NativeClientSavedRunState, NativeClientSavedRunStateIssue] {
  let reads = operations.map(value => value.reads)
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      ReadRunMaterials,
      capture~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  match
    self.journal.lookup_submitted_intent_with_operations(
      self.epoch,
      reference,
      authority.scope,
      authority.current_for(self.journal, request),
      now,
      operations~,
    ) {
    Ok(Submitted(value)) if value.run_admission is Some(_) => ()
    Ok(_) => return Err(Unavailable)
    Err(issue) => return Err(Journal(issue))
  }
  self.journal
  .transaction_with_reads(
    () => {
      if !authority.current_for(self.journal, request) {
        return Err(AuthorizationDenied)
      }
      let read : Result[NativeClientSavedRunState?, NativeClientRunJournalIssue] = match
        self.journal.saved_run_state_locked(reference, request, reads~) {
        Ok((original, run)) => restore_native_saved_run_state(original, run)
        Err(issue) => Err(issue)
      }
      if !authority.current_for(self.journal, request) {
        return Err(AuthorizationDenied)
      }
      read
    },
    reads~,
  )
  .map_err(issue => NativeClientSavedRunStateIssue::Journal(issue))
  .bind(value => {
    match value {
      Some(value) => Ok(value)
      None => Err(Unavailable)
    }
  })
}
