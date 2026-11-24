///|
// Shared read-only carrier. No Store mutation, prepared attempt or cleanup
// authority can be recovered from an observation of a committed index.
priv struct NativeEffectfulRunStateOriginal {
  service : NativeRunPublicationService
  evidence : NativeEffectfulPublicationEvidence
  intent : NativeRunPublicationIntent
  original_request : @publication.PublicationContract
  still_current : () -> Bool
}

///|
/// SAME candidate/current/release protocol; Host terminal authorization stays separate.
pub fn NativePreparedEffectfulRunPublication::prepare_run_state_candidate(
  self : NativePreparedEffectfulRunPublication,
  observed_at : String,
  max_workspace : Int,
  quantum : Int,
  max_rounds : Int,
) -> Result[NativeRunStateCandidate, NativeRunStateCandidateIssue] {
  let original : NativeEffectfulRunStateOriginal = {
    service: self.service,
    evidence: self.evidence,
    intent: self.intent,
    original_request: self.preparation.request,
    still_current: () => !self.cancelled && !self.closing,
  }
  original.prepare_run_state_candidate(
    observed_at, max_workspace, quantum, max_rounds,
  )
}

///|
/// Inspect the already committed occurrence without issuing a request,
/// attempt, Result writer or Store mutation. The Host retains independent
/// Publisher/RunRead currentness and the actual original Store selection.
pub fn prepare_recovered_effectful_run_state_candidate(
  service : NativeRunPublicationService,
  evidence : NativeEffectfulPublicationEvidence,
  intent : NativeRunPublicationIntent,
  original_request : @publication.PublicationContract,
  observed_at : String,
  max_workspace : Int,
  quantum : Int,
  max_rounds : Int,
) -> Result[NativeRunStateCandidate, NativeRunStateCandidateIssue] {
  let original : NativeEffectfulRunStateOriginal = {
    service,
    evidence,
    intent,
    original_request,
    still_current: () => service.store.retained_data_current() is Ok(_),
  }
  original.prepare_run_state_candidate(
    observed_at, max_workspace, quantum, max_rounds,
  )
}

///|
fn NativeEffectfulRunStateOriginal::prepare_run_state_candidate(
  self : Self,
  observed_at : String,
  max_workspace : Int,
  quantum : Int,
  max_rounds : Int,
) -> Result[NativeRunStateCandidate, NativeRunStateCandidateIssue] {
  if max_workspace < 1 || quantum < 1 || max_rounds < 1 {
    return Err(InvalidLimits)
  }
  if !(self.still_current)() {
    return Err(Unavailable)
  }
  let service = self.service
  let evidence = self.evidence
  match
    authorize(
      service,
      self.intent,
      evidence.run_definition,
      self.original_request,
      "request",
      None,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Publication(issue))
  }
  if !(self.still_current)() {
    return Err(Publication(AccessDenied))
  }
  let index = match
    service.store.inspect_committed_publication(
      self.intent.namespace_id,
      self.intent.authority_scope_cid,
      @publication.publication_contract_identity(evidence.run_definition),
      service.max_wire_bytes,
      service.max_nodes,
      service.max_depth,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Unavailable)
    Err(issue) => return Err(Publication(Store(issue)))
  }
  let projected = match @publication.project_public_index_read(index) {
    Ok(value) => value
    Err(issue) => return Err(Publication(Projection(issue)))
  }
  let stored_request = match
    service.store.read_publication_contract(
      "publication_request",
      projected.publication_request_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Publication(Store(issue)))
  }
  let stored_attempt = match
    service.store.read_publication_contract(
      "publication_attempt",
      projected.publication_attempt_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Publication(Store(issue)))
  }
  if @publication.publication_contract_identity(stored_request) !=
    @publication.publication_contract_identity(self.original_request) {
    return Err(Publication(CommitConflict))
  }
  let owner : @local.ClientProgramValidation? = None
  let validation = match
    @publication.prepare_retained_effectful_publication_commit_check(
      evidence.final_evidence,
      evidence.bindings,
      stored_request,
      stored_attempt,
      index,
      service.max_wire_bytes,
      service.max_nodes,
      service.max_depth,
      max_workspace,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(Publication(Store(@store.EffectfulPublication(issue))))
  }

  match
    advance_native_state_validation(validation, quantum, max_rounds, owner~) {
    Ok(_) => ()
    Err(issue) => {
      cancel_native_state_validation(validation, owner)
      return Err(issue)
    }
  }
  let view = match validation.finish_view() {
    Ok(value) => value
    Err(issue) => {
      cancel_native_state_validation(validation, owner)
      return Err(Publication(Commit(issue)))
    }
  }
  match
    validation.begin_observed_commit(
      view, stored_request, stored_attempt, index,
    ) {
    Ok(_) => ()
    Err(issue) => {
      validation.release_view(view) |> ignore
      cancel_native_state_validation(validation, owner)
      return Err(Publication(Commit(issue)))
    }
  }
  let outcome = match
    advance_native_observed_state_validation(
      validation,
      view,
      quantum,
      max_rounds,
      owner~,
    ) {
    Err(issue) => Err(issue)
    Ok(_) =>
      self.finish_observed_run_state(
        validation,
        view,
        stored_request,
        stored_attempt,
        index,
        observed_at,
        owner~,
      )
  }
  // On success transfer only the same bounded Core loan to the candidate;
  // its typed Host consumer retires it on every outcome. No state wire exists
  // yet. Failed preparation preserves the original release/cancel sequence.
  match outcome {
    Ok(candidate) => Ok(candidate)
    Err(issue) => {
      let child_release = validation.release_observed_commit(view)
      let view_release = validation.release_view(view)
      cancel_native_state_validation(validation, owner)
      match child_release {
        Ok(_) => ()
        Err(issue) => return Err(Publication(Commit(issue)))
      }
      match view_release {
        Ok(_) => ()
        Err(issue) => return Err(Publication(Commit(issue)))
      }
      Err(issue)
    }
  }
}

///|
fn NativeEffectfulRunStateOriginal::finish_observed_run_state(
  self : Self,
  validation : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  stored_request : @publication.PublicationContract,
  stored_attempt : @publication.PublicationContract,
  index : @publication.PublicationContract,
  observed_at : String,
  owner? : @local.ClientProgramValidation? = None,
) -> Result[NativeRunStateCandidate, NativeRunStateCandidateIssue] {
  match validation.finish_observed_commit(view) {
    Ok(_) => ()
    Err(issue) => return Err(Publication(Commit(issue)))
  }
  match
    authorize(
      self.service,
      self.intent,
      self.evidence.run_definition,
      self.original_request,
      "return_committed",
      Some(index),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Publication(issue))
  }
  if !(self.still_current)() ||
    !native_state_validation_loan_current(validation, owner) {
    return Err(Publication(AccessDenied))
  }
  // After all user callbacks, use the actual non-callback Store generation/
  // lifecycle checks. A callback that retires the Store cannot leak a view.
  match
    self.service.store.observe_publication_payload_facts(
      self.evidence.bindings,
      self.evidence.binding_schema_wires,
      self.service.max_wire_bytes,
      self.service.max_nodes,
      self.service.max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Publication(Store(issue)))
  }
  let current_index = match
    self.service.store.inspect_committed_publication(
      self.intent.namespace_id,
      self.intent.authority_scope_cid,
      @publication.publication_contract_identity(self.evidence.run_definition),
      self.service.max_wire_bytes,
      self.service.max_nodes,
      self.service.max_depth,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Unavailable)
    Err(issue) => return Err(Publication(Store(issue)))
  }
  if @publication.publication_contract_identity(current_index) !=
    @publication.publication_contract_identity(index) {
    return Err(Publication(CommitConflict))
  }
  let count = match validation.view_count(view) {
    Ok(value) => value
    Err(issue) => return Err(Publication(Commit(issue)))
  }
  for ordinal in 0..<count {
    let original = match validation.view_contract(view, ordinal) {
      Ok(value) => value
      Err(issue) => return Err(Publication(Commit(issue)))
    }
    match
      self.service.store.read_publication_contract(
        @publication.publication_contract_name(original),
        @publication.publication_contract_identity(original),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Publication(Store(issue)))
    }
  }
  Ok({
    definition: self.evidence.run_definition,
    validation,
    preparation: owner,
    view,
    observed_at,
    released: false,
    pending: Effectful(self),
    request: stored_request,
    attempt: stored_attempt,
    index,
  })
}
