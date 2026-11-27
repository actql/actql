///|
/// Saved original outcome only. The SQL Submission metadata revision is never
/// exposed as a public control revision. Control remains the actual Run row.
struct NativeClientSavedRunState {
  original : @host.ClientRunStateOriginal?
  state_wire : String
  control_revision : Int64
}

///|
pub fn NativeClientSavedRunState::wire(
  self : NativeClientSavedRunState,
) -> String {
  self.state_wire
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
  ModelProofRequired
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
  settlement? : NativeLocalEffectPublicationSettlement? = None,
) -> Result[NativeClientSavedRunState, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  self.transaction_with_reads(
    () => {
      if (observed.effect_outcomes is Some(_)) != (settlement is Some(_)) {
        return Err(Checkpoint(InvalidMaterial))
      }
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
      if settlement is Some(effect) {
        if !(effect.current)() {
          return Err(AuthorizationDenied)
        }
        match
          self.require_current_file_effect_settlement_locked(
            effect.claim,
            @env.now().reinterpret_as_int64(),
            reads~,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        match self.require_file_effect_completion_locked(run, effect, reads) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      let saved = match
        self.retain_run_state_locked(
          original,
          run,
          observed.wire(),
          Some(observed.original_manifest()),
          () => {
            authority.current_for(self, request) &&
            observed.publisher.current_in_owned_transaction()
          },
          operations~,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      // Ordinary Saved-state metadata continues to leave the Run alone.
      // The matched saved File continuation also settles its own claim.
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
      match settlement {
        None => Ok(saved)
        Some(effect) =>
          self
          .finish_file_effect_resume_locked(
            run,
            observed,
            saved.state_wire,
            effect,
            operations,
          )
          .map(completed => { ..saved, control_revision: completed.revision, })
      }
    },
    reads~,
  )
}

///|
// Both successful publication and an authenticated unpublished observation
// replace only the metadata of the same original Submission.
fn NativeClientRunJournal::retain_run_state_locked(
  self : NativeClientRunJournal,
  original : NativeClientSubmittedIntentRecord,
  run : NativeClientRunRecord,
  candidate_wire : String,
  manifest : @publication.PublicationContract?,
  current : () -> Bool,
  operations? : NativeClientJournalOperationAccess? = None,
  model_failure? : @publication.BoundModelHttpFailure? = None,
  model_unknown? : (String, String)? = None,
) -> Result[NativeClientSavedRunState, NativeClientRunJournalIssue] {
  guard self.transaction_active else { return Err(CustodyLost) }
  if (manifest is Some(_) && model_failure is Some(_)) ||
    (
      model_unknown is Some(_) &&
      (manifest is Some(_) || model_failure is Some(_))
    ) {
    return Err(CustodyLost)
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
      candidate_wire, run_id, prior_revision, 65536, 8192, 64,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let revision = match observation.next_revision(prior_key, prior_revision) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let state_wire = match observation.wire(revision) {
    Ok(value) => value
    Err(_) => return Err(CapacityExceeded)
  }
  let prepared = match (manifest, model_unknown) {
    (Some(original), None) =>
      @host.prepare_client_run_state_original(
        run.definition,
        original,
        state_wire,
      )
    (None, Some((attempt, entry_digest))) =>
      @host.prepare_client_dependent_model_unknown_run_state_original(
        run.definition,
        state_wire,
        attempt,
        entry_digest,
      )
    _ =>
      @host.prepare_client_unpublished_run_state_original(
        run.definition,
        state_wire,
        model_failure~,
      )
  }
  let state = match prepared {
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
  if !current() {
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
          original.reference.request_id,
          original.revision,
          body,
          operations,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
    }
  }
  Ok({
    original: Some(state),
    state_wire: state.state_wire(),
    control_revision: run.revision,
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
  settlement? : NativeLocalEffectPublicationSettlement? = None,
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
    settlement~,
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
  model_store? : (@publication_store.Store, String, NativeLocalStoreOperation)? = None,
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
      let read = self.journal
        .saved_run_state_locked(reference, request, reads~)
        .bind(saved => {
          let (submitted, run) = saved
          guard submitted.restored_state_original is Some(retained) &&
            retained.requires_model_proof() else {
            return restore_native_saved_run_state(submitted, run).map(value => {
              (value, false)
            })
          }
          match (capture, reads, model_store) {
            (
              Some(captured),
              Some(physical),
              Some((store, namespace_id, operation)),
            ) => {
              let failure = Ref(None)
              let state = if retained.requires_dependent_model_unknown_proof() {
                let resolve_unknown = (attempt, entry_digest) => {
                  match
                    captured.restore_saved_dependent_model_unknown_locked(
                      authority,
                      run,
                      store,
                      namespace_id,
                      operation,
                      (attempt, entry_digest),
                      physical,
                    ) {
                    Ok(_) => true
                    Err(issue) => {
                      failure.val = Some(issue)
                      false
                    }
                  }
                }
                restore_native_saved_run_state(
                  submitted,
                  run,
                  resolve_dependent_model_unknown=Some(resolve_unknown),
                )
              } else {
                let resolve = (attempt, raw) => {
                  match
                    captured.restore_saved_model_failure_locked(
                      authority,
                      run,
                      store,
                      namespace_id,
                      operation,
                      (attempt, raw),
                      physical,
                    ) {
                    Ok(value) => Some(value)
                    Err(issue) => {
                      failure.val = Some(issue)
                      None
                    }
                  }
                }
                restore_native_saved_run_state(
                  submitted,
                  run,
                  resolve_model_failure=Some(resolve),
                )
              }
              match failure.val {
                Some(issue) => Err(issue)
                None => state.map(value => (value, false))
              }
            }
            (_, _, None) => Ok((None, true))
            _ => Err(CustodyLost)
          }
        })
      if !authority.current_for(self.journal, request) {
        return Err(AuthorizationDenied)
      }
      read
    },
    reads~,
  )
  .map_err(issue => NativeClientSavedRunStateIssue::Journal(issue))
  .bind(result => {
    match result {
      (Some(value), _) => Ok(value)
      (None, true) => Err(ModelProofRequired)
      (None, false) => Err(Unavailable)
    }
  })
}
