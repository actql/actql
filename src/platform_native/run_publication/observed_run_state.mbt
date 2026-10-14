///|
/// Read-only original execution observation, never an authority, Store ACK,
/// cleanup receipt, Result availability fact or a resumable compilation.
struct NativeObservedRunState {
  definition : @publication.PublicationContract
  wire : String
  original : @publication_host.ClientRunStateOriginal
  store : @store.Store
  namespace_id : String
  scope : String
}

///|
pub(all) enum NativeObservedRunStateIssue {
  Unavailable
  InvalidLimits
  ValidationLimit
  Publication(NativeRunPublicationIssue)
  State(@publication.ObservedPublicationRunStateIssue)
}

///|
pub fn NativeObservedRunState::definition_cid(
  self : NativeObservedRunState,
) -> String {
  @publication.publication_contract_identity(self.definition)
}

///|
pub fn NativeObservedRunState::wire(self : NativeObservedRunState) -> String {
  self.wire
}

///|
/// Same actual Store and original request/namespace, not a permission predicate.
pub fn NativeObservedRunState::matches_original_store(
  self : NativeObservedRunState,
  store : @store.Store,
  namespace_id : String,
  scope : String,
  definition_cid : String,
) -> Bool {
  physical_equal(self.store, store) &&
  self.namespace_id == namespace_id &&
  self.scope == scope &&
  self.definition_cid() == definition_cid
}

///|
pub fn NativeObservedRunState::original_wire(
  self : NativeObservedRunState,
) -> String {
  self.original.wire()
}

///|
fn advance_native_state_validation(
  preparation : @publication.PublicationCommitPreparation,
  quantum : Int,
  max_rounds : Int,
) -> Result[Unit, NativeObservedRunStateIssue] {
  for _ in 0..<max_rounds {
    match preparation.advance(quantum) {
      Ok((true, _)) => return Ok(())
      Ok((false, _)) => ()
      Err(issue) => return Err(Publication(Commit(issue)))
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
) -> Result[Unit, NativeObservedRunStateIssue] {
  for _ in 0..<max_rounds {
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
/// actual same Store chain. Unknown commit response is not resend permission;
/// this method only inspects existing stored contracts, never calls commit.
/// The trusted Host supplies its actual current RunRead predicate separately
/// from the existing Publisher. Neither an old Allow nor index existence is
/// authorization. Caller work/loans stay within its original workspace profile.
pub fn NativePreparedCapturedRunPublication::observe_run_state(
  self : NativePreparedCapturedRunPublication,
  observed_at : String,
  max_workspace : Int,
  quantum : Int,
  max_rounds : Int,
  current_run_read : () -> Bool,
) -> Result[NativeObservedRunState, NativeObservedRunStateIssue] {
  if max_workspace < 1 || quantum < 1 || max_rounds < 1 {
    return Err(InvalidLimits)
  }
  if self.cancelled {
    return Err(Unavailable)
  }
  let service = self.service
  let evidence = self.evidence
  if !current_run_read() {
    return Err(Publication(AccessDenied))
  }
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
  if self.cancelled || !current_run_read() {
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
  let validation = @publication.start_effect_free_publication_commit_check(
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
  match advance_native_state_validation(validation, quantum, max_rounds) {
    Ok(_) => ()
    Err(issue) => {
      validation.cancel()
      return Err(issue)
    }
  }
  let view = match validation.finish_view() {
    Ok(value) => value
    Err(issue) => {
      validation.cancel()
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
      validation.cancel()
      return Err(Publication(Commit(issue)))
    }
  }
  let outcome = match
    advance_native_observed_state_validation(
      validation, view, quantum, max_rounds,
    ) {
    Err(issue) => Err(issue)
    Ok(_) =>
      self.finish_observed_run_state(
        validation, view, index, observed_at, current_run_read,
      )
  }
  // These nominal metadata loans contain no payload stream. Retire the same
  // child and view on every outcome; cancellation does not acknowledge Store
  // or work cleanup, which remains with the original pending publication.
  let child_release = validation.release_observed_commit(view)
  let view_release = validation.release_view(view)
  validation.cancel()
  match child_release {
    Ok(_) => ()
    Err(issue) => return Err(Publication(Commit(issue)))
  }
  match view_release {
    Ok(_) => ()
    Err(issue) => return Err(Publication(Commit(issue)))
  }
  outcome
}

///|
fn NativePreparedCapturedRunPublication::finish_observed_run_state(
  self : NativePreparedCapturedRunPublication,
  validation : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  index : @publication.PublicationContract,
  observed_at : String,
  current_run_read : () -> Bool,
) -> Result[NativeObservedRunState, NativeObservedRunStateIssue] {
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
  if !current_run_read() || self.cancelled {
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
  let wire = match
    validation.observed_run_state_wire(
      view,
      observed_at,
      self.service.max_wire_bytes,
      self.service.max_nodes,
      self.service.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(State(issue))
  }
  let original = match
    @publication_host.prepare_client_run_state_original(
      self.evidence.run_definition,
      self.evidence.manifest,
      wire,
    ) {
    Ok(value) => value
    Err(_) => return Err(Unavailable)
  }
  Ok({
    definition: self.evidence.run_definition,
    wire,
    original,
    store: self.service.store,
    namespace_id: self.intent.namespace_id,
    scope: self.intent.authority_scope_cid,
  })
}
