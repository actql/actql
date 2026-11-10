///|
/// Unfinalized bounded physical metadata candidate. Only the concrete Local
/// Host may accept it after both current Publisher and RunRead checks. It is
/// never finalized authority, Store ACK, cleanup or current Result availability.
struct NativeRunStateCandidate {
  definition : @publication.PublicationContract
  validation : @publication.PublicationCommitPreparation
  preparation : @local.ClientProgramValidation?
  view : @publication.PublicationCommitReadView
  observed_at : String
  mut released : Bool
  pending : NativeRunStateCandidateOriginal
  request : @publication.PublicationContract
  attempt : @publication.PublicationContract
  index : @publication.PublicationContract
}

///|
pub(all) enum NativeRunStateCandidateIssue {
  Unavailable
  InvalidLimits
  ValidationLimit
  Publication(NativeRunPublicationIssue)
  State(@publication.ObservedPublicationRunStateIssue)
}

///|
/// Borrow only existing nominal Core inputs, never emit a RunState wire here.
/// The typed Local Host performs terminal current before the existing Core
/// projection. These inputs themselves contain no authorization permission.
pub fn NativeRunStateCandidate::original_metadata(
  self : NativeRunStateCandidate,
) -> (@publication.PublicationContract, @publication.PublicationContract) {
  (self.definition, self.pending.manifest())
}

///|
/// Existing bounded Core observation loan. Callers must release this candidate
/// on every outcome. Exposing a Core proof does not issue current read authority.
pub fn NativeRunStateCandidate::projection_materials(
  self : NativeRunStateCandidate,
) -> Result[
  (
    @publication.PublicationCommitPreparation,
    @publication.PublicationCommitReadView,
    String,
    Int,
    Int,
    Int,
  ),
  NativeRunStateCandidateIssue,
] {
  if self.released ||
    !native_state_validation_loan_current(self.validation, self.preparation) {
    return Err(Unavailable)
  }
  Ok(
    (
      self.validation,
      self.view,
      self.observed_at,
      self.pending.service().max_wire_bytes,
      self.pending.service().max_nodes,
      self.pending.service().max_depth,
    ),
  )
}

///|
/// Retire the same original Core child/view, without Store or work cleanup.
pub fn NativeRunStateCandidate::release(
  self : NativeRunStateCandidate,
) -> Result[Unit, NativeRunStateCandidateIssue] {
  if self.released {
    return Err(Unavailable)
  }
  self.released = true
  let child = self.validation.release_observed_commit(self.view)
  let view = self.validation.release_view(self.view)
  cancel_native_state_validation(self.validation, self.preparation)
  match child {
    Ok(_) => ()
    Err(issue) => return Err(Publication(Commit(issue)))
  }
  match view {
    Ok(_) => Ok(())
    Err(issue) => Err(Publication(Commit(issue)))
  }
}

///|
pub fn NativeRunStateCandidate::original_client_request(
  self : NativeRunStateCandidate,
) -> @publication_host.ClientRequestIdentity? {
  self.pending.service().client_request
}

///|
/// Exact original publication context, not an authorization outcome. A copied
/// CID cannot select a foreign Store/request or replace the adopted publisher.
pub fn NativeRunStateCandidate::matches_original_publisher(
  self : NativeRunStateCandidate,
  store : @store.Store,
  namespace_id : String,
  scope : String,
  definition_cid : String,
  policy_cid : String,
  target_cid : String,
) -> Bool {
  let pending = self.pending
  physical_equal(pending.service().store, store) &&
  pending.intent().namespace_id == namespace_id &&
  pending.intent().authority_scope_cid == scope &&
  pending.intent().publication_policy_cid == policy_cid &&
  pending.intent().publication_target_cid == target_cid &&
  @publication.publication_contract_identity(self.definition) == definition_cid
}

///|
/// Callback-free same-original Store/lifetime checks after the Host's actual
/// current predicates. No grant or finalized authorization is issued here.
pub fn NativeRunStateCandidate::require_original_store_current(
  self : NativeRunStateCandidate,
) -> Result[Unit, NativeRunStateCandidateIssue] {
  let pending = self.pending
  if self.released ||
    pending.cancelled() ||
    !native_state_validation_loan_current(self.validation, self.preparation) {
    return Err(Unavailable)
  }
  match
    pending.service().store.observe_publication_payload_facts(
      pending.bindings(),
      pending.binding_schema_wires(),
      pending.service().max_wire_bytes,
      pending.service().max_nodes,
      pending.service().max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Publication(Store(issue)))
  }
  let store = pending.service().store
  match
    store.inspect_committed_publication(
      pending.intent().namespace_id,
      pending.intent().authority_scope_cid,
      @publication.publication_contract_identity(self.definition),
      pending.service().max_wire_bytes,
      pending.service().max_nodes,
      pending.service().max_depth,
    ) {
    Ok(Some(current)) if @publication.publication_contract_identity(current) ==
      @publication.publication_contract_identity(self.index) => ()
    Ok(_) => return Err(Publication(CommitConflict))
    Err(issue) => return Err(Publication(Store(issue)))
  }
  let check = (original : @publication.PublicationContract) => {
    store
    .read_publication_contract(
      @publication.publication_contract_name(original),
      @publication.publication_contract_identity(original),
    )
    .map(_ => ())
    .map_err(issue => NativeRunStateCandidateIssue::Publication(Store(issue)))
  }
  // Borrow the original evidence arrays, without another view-array copy.
  for
    originals in [
      pending.definitions(),
      pending.artifacts(),
      pending.derivations(),
      pending.orderings(),
      pending.retentions(),
      pending.bindings(),
    ] {
    for original in originals {
      match check(original) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  for
    original in [
      self.definition,
      pending.invocation(),
      pending.manifest(),
      pending.receipt(),
      pending.captured_run(),
      self.request,
      self.attempt,
      self.index,
    ] {
    match check(original) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok(())
}

///|
fn advance_native_state_validation(
  preparation : @publication.PublicationCommitPreparation,
  quantum : Int,
  max_rounds : Int,
  owner? : @local.ClientProgramValidation? = None,
) -> Result[Unit, NativeRunStateCandidateIssue] {
  for _ in 0..<max_rounds {
    let progress = match owner {
      Some(original) =>
        @local.advance_program_validation(original, quantum).map_err(issue => {
          NativeRunStateCandidateIssue::Publication(Preparation(issue))
        })
      None =>
        preparation
        .advance(quantum)
        .map_err(issue => {
          NativeRunStateCandidateIssue::Publication(Commit(issue))
        })
    }
    match progress {
      Ok((true, _)) => return Ok(())
      Ok((false, _)) => ()
      Err(issue) => return Err(issue)
    }
  }
  Err(ValidationLimit)
}

///|
fn advance_native_observed_state_validation(
  preparation : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  quantum : Int,
  max_rounds : Int,
  owner? : @local.ClientProgramValidation? = None,
) -> Result[Unit, NativeRunStateCandidateIssue] {
  for _ in 0..<max_rounds {
    if !native_state_validation_loan_current(preparation, owner) {
      return Err(Unavailable)
    }
    match preparation.advance_observed_commit(view, quantum) {
      Ok((true, _)) => return Ok(())
      Ok((false, _)) => ()
      Err(issue) => return Err(Publication(Commit(issue)))
    }
  }
  Err(ValidationLimit)
}

///|
/// Use only this opaque pending Owner's original completed evidence and the
/// actual same Store chain. Unknown commit response is not resend permission.
/// Existing Publisher callbacks guard candidate preparation only; they cannot
/// finalize both Publisher and RunRead authorization. There is no caller Bool
/// RunRead port or finalized wire result. The concrete typed Local Host owns
/// terminal acceptance after all callbacks. Original workspace limits remain.
pub fn NativePreparedCapturedRunPublication::prepare_run_state_candidate(
  self : NativePreparedCapturedRunPublication,
  observed_at : String,
  max_workspace : Int,
  quantum : Int,
  max_rounds : Int,
) -> Result[NativeRunStateCandidate, NativeRunStateCandidateIssue] {
  if max_workspace < 1 || quantum < 1 || max_rounds < 1 {
    return Err(InvalidLimits)
  }
  if self.cancelled {
    return Err(Unavailable)
  }
  let service = self.service
  let evidence = self.evidence
  match
    authorize(
      service,
      self.intent,
      evidence.run_definition,
      self.preparation.request,
      "request",
      None,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Publication(issue))
  }
  if self.cancelled {
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
    @publication.publication_contract_identity(self.preparation.request) {
    return Err(Publication(CommitConflict))
  }
  let owner = match self.capture {
    None => None
    Some(capture) => {
      let value = match
        @local.prepare_program_commit_validation(
          capture,
          evidence.run_definition,
          evidence.invocation,
          evidence.definitions,
          evidence.artifacts,
          evidence.derivations,
          evidence.orderings,
          evidence.retentions,
          evidence.bindings,
          evidence.manifest,
          evidence.receipt,
          evidence.captured_run,
          stored_request,
          stored_attempt,
          index,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Publication(Preparation(issue)))
      }
      match
        @local.start_program_validation(
          value,
          max_workspace=Some(max_workspace),
        ) {
        Ok(_) => Some(value)
        Err(issue) => {
          @local.cancel_program_validation(value)
          return Err(Publication(Preparation(issue)))
        }
      }
    }
  }
  let validation = match owner {
    Some(value) =>
      match @local.borrow_program_commit_validation(value) {
        Some(checker) => checker
        None => {
          @local.cancel_program_validation(value)
          return Err(Unavailable)
        }
      }
    None =>
      @publication.start_effect_free_publication_commit_check(
        evidence.run_definition,
        evidence.invocation,
        evidence.definitions,
        evidence.artifacts,
        evidence.derivations,
        evidence.orderings,
        evidence.retentions,
        evidence.bindings,
        evidence.manifest,
        evidence.receipt,
        evidence.captured_run,
        stored_request,
        stored_attempt,
        index,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
        max_workspace,
      )
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
fn NativePreparedCapturedRunPublication::finish_observed_run_state(
  self : NativePreparedCapturedRunPublication,
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
      self.preparation.request,
      "return_committed",
      Some(index),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Publication(issue))
  }
  if self.cancelled || !native_state_validation_loan_current(validation, owner) {
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
    pending: EffectFree(self),
    request: stored_request,
    attempt: stored_attempt,
    index,
  })
}

///|
fn native_state_validation_loan_current(
  checker : @publication.PublicationCommitPreparation,
  owner : @local.ClientProgramValidation?,
) -> Bool {
  match owner {
    None => true
    Some(value) =>
      @local.borrow_program_commit_validation(value) is Some(original) &&
      physical_equal(original, checker)
  }
}

///|
fn cancel_native_state_validation(
  checker : @publication.PublicationCommitPreparation,
  owner : @local.ClientProgramValidation?,
) -> Unit {
  match owner {
    None => checker.cancel()
    Some(value) => @local.cancel_program_validation(value)
  }
}

///|
priv enum NativeRunStateCandidateOriginal {
  EffectFree(NativePreparedCapturedRunPublication)
  Effectful(NativePreparedEffectfulRunPublication)
}

///|
fn NativeRunStateCandidateOriginal::service(
  self : NativeRunStateCandidateOriginal,
) -> NativeRunPublicationService {
  match self {
    EffectFree(value) => value.service
    Effectful(value) => value.service
  }
}

///|
fn NativeRunStateCandidateOriginal::intent(
  self : NativeRunStateCandidateOriginal,
) -> NativeRunPublicationIntent {
  match self {
    EffectFree(value) => value.intent
    Effectful(value) => value.intent
  }
}

///|
fn NativeRunStateCandidateOriginal::cancelled(
  self : NativeRunStateCandidateOriginal,
) -> Bool {
  match self {
    EffectFree(value) => value.cancelled
    Effectful(value) => value.cancelled || value.closing
  }
}

///|
fn NativeRunStateCandidateOriginal::manifest(
  self : NativeRunStateCandidateOriginal,
) -> @publication.PublicationContract {
  match self {
    EffectFree(value) => value.evidence.manifest
    Effectful(value) => value.evidence.manifest
  }
}

///|
fn NativeRunStateCandidateOriginal::definitions(
  self : NativeRunStateCandidateOriginal,
) -> Array[@publication.PublicationContract] {
  match self {
    EffectFree(value) => value.evidence.definitions
    Effectful(value) => value.evidence.definitions
  }
}

///|
fn NativeRunStateCandidateOriginal::artifacts(
  self : NativeRunStateCandidateOriginal,
) -> Array[@publication.PublicationContract] {
  match self {
    EffectFree(value) => value.evidence.artifacts
    Effectful(value) => value.evidence.artifacts
  }
}

///|
fn NativeRunStateCandidateOriginal::derivations(
  self : NativeRunStateCandidateOriginal,
) -> Array[@publication.PublicationContract] {
  match self {
    EffectFree(value) => value.evidence.derivations
    Effectful(value) => value.evidence.derivations
  }
}

///|
fn NativeRunStateCandidateOriginal::orderings(
  self : NativeRunStateCandidateOriginal,
) -> Array[@publication.PublicationContract] {
  match self {
    EffectFree(value) => value.evidence.orderings
    Effectful(value) => value.evidence.orderings
  }
}

///|
fn NativeRunStateCandidateOriginal::retentions(
  self : NativeRunStateCandidateOriginal,
) -> Array[@publication.PublicationContract] {
  match self {
    EffectFree(value) => value.evidence.retentions
    Effectful(value) => value.evidence.retentions
  }
}

///|
fn NativeRunStateCandidateOriginal::bindings(
  self : NativeRunStateCandidateOriginal,
) -> Array[@publication.PublicationContract] {
  match self {
    EffectFree(value) => value.evidence.bindings
    Effectful(value) => value.evidence.bindings
  }
}

///|
fn NativeRunStateCandidateOriginal::binding_schema_wires(
  self : NativeRunStateCandidateOriginal,
) -> Array[String] {
  match self {
    EffectFree(value) => value.evidence.binding_schema_wires
    Effectful(value) => value.evidence.binding_schema_wires
  }
}

///|
fn NativeRunStateCandidateOriginal::invocation(
  self : NativeRunStateCandidateOriginal,
) -> @publication.PublicationContract {
  match self {
    EffectFree(value) => value.evidence.invocation
    Effectful(value) => value.evidence.invocation
  }
}

///|
fn NativeRunStateCandidateOriginal::receipt(
  self : NativeRunStateCandidateOriginal,
) -> @publication.PublicationContract {
  match self {
    EffectFree(value) => value.evidence.receipt
    Effectful(value) => value.evidence.receipt
  }
}

///|
fn NativeRunStateCandidateOriginal::captured_run(
  self : NativeRunStateCandidateOriginal,
) -> @publication.PublicationContract {
  match self {
    EffectFree(value) => value.evidence.captured_run
    Effectful(value) => value.evidence.captured_run
  }
}
