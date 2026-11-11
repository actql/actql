///|
/// Read-only original observation accepted by this concrete adopted Host.
/// This snapshot grants no future access, Store ACK, cleanup or retry. Saving
/// rechecks both original purposes and current custody through the same Owner.
struct NativeLocalObservedRunState {
  host : NativeLocalHostConnection
  publisher : NativeLocalPublisherBinding
  read_authority : NativeLocalPolicyAuthority
  request : @host.ClientRequestIdentity
  definition : @publication.PublicationContract
  manifest : @publication.PublicationContract
  receipt : @publication.PublicationContract
  wire : String
}

///|
pub(all) enum NativeLocalObservedRunStateIssue {
  AuthorizationDenied
  ForeignOriginal
  OriginalUnavailable
  Journal(NativeClientRunJournalIssue)
  Candidate(@native_publication.NativeRunStateCandidateIssue)
}

///|
pub fn NativeLocalObservedRunState::wire(
  self : NativeLocalObservedRunState,
) -> String {
  self.wire
}

///|
pub fn NativeLocalObservedRunState::definition_cid(
  self : NativeLocalObservedRunState,
) -> String {
  @publication.publication_contract_identity(self.definition)
}

///|
/// Original Manifest metadata, not a read grant or current availability.
pub fn NativeLocalObservedRunState::original_manifest(
  self : NativeLocalObservedRunState,
) -> @publication.PublicationContract {
  self.manifest
}

///|
// Concrete Owner checks, never public arbitrary callbacks or cached Allow.
fn NativeLocalObservedRunState::require_current_for(
  self : NativeLocalObservedRunState,
  host : NativeLocalHostConnection,
  request : @host.ClientRequestIdentity,
) -> Bool {
  physical_equal(self.host, host) &&
  @host.client_request_identity_relation(self.request, request) ==
  @host.SameRequest &&
  self.publisher.current() &&
  self.read_authority.current_for(host.journal, request)
}

///|
/// Accept the lower bounded candidate only at the original typed Host. The
/// publisher's actual original Account, selected file, request, Run and Store
/// remain separate from current RunRead. No bool supplier can finalize state.
pub fn NativeLocalHostConnection::observe_publication_run_state(
  self : NativeLocalHostConnection,
  publisher : NativeLocalPublisherBinding,
  pending : @native_publication.NativePreparedCapturedRunPublication,
  observed_at : String,
  max_workspace : Int,
  quantum : Int,
  max_rounds : Int,
) -> Result[NativeLocalObservedRunState, NativeLocalObservedRunStateIssue] {
  let authority = match
    self.prepare_publication_observation_authority(publisher) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let candidate = match
    pending.prepare_run_state_candidate(
      observed_at, max_workspace, quantum, max_rounds,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let result = self.finalize_observed_run_state_candidate(
    publisher, authority, candidate,
  )
  match candidate.release() {
    Ok(_) => result
    Err(issue) => Err(Candidate(issue))
  }
}

///|
/// SAME Host observer for an original Effectful pending publication. The
/// existing finalizer preserves publisher and independent Read authority;
/// no fresh publisher is manufactured for an already completed Saved Run.
pub fn NativeLocalHostConnection::observe_effectful_publication_run_state(
  self : NativeLocalHostConnection,
  publisher : NativeLocalPublisherBinding,
  pending : @native_publication.NativePreparedEffectfulRunPublication,
  observed_at : String,
  max_workspace : Int,
  quantum : Int,
  max_rounds : Int,
) -> Result[NativeLocalObservedRunState, NativeLocalObservedRunStateIssue] {
  let authority = match
    self.prepare_publication_observation_authority(publisher) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let candidate = match
    pending.prepare_run_state_candidate(
      observed_at, max_workspace, quantum, max_rounds,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let result = self.finalize_observed_run_state_candidate(
    publisher, authority, candidate,
  )
  match candidate.release() {
    Ok(_) => result
    Err(issue) => Err(Candidate(issue))
  }
}

///|
fn NativeLocalHostConnection::prepare_publication_observation_authority(
  self : NativeLocalHostConnection,
  publisher : NativeLocalPublisherBinding,
) -> Result[NativeLocalPolicyAuthority, NativeLocalObservedRunStateIssue] {
  if !physical_equal(publisher.authority.host, self) ||
    !(publisher.authority.purpose is PublishRun) {
    return Err(ForeignOriginal)
  }
  let request = publisher.request
  let authority = match
    native_local_policy_authority_for(
      self,
      publisher.authority.crypto,
      publisher.authority.principal,
      publisher.authority.connection,
      request,
      ReadRunMaterials,
      capture=publisher.authority.capture,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if !publisher.current() {
    return Err(AuthorizationDenied)
  }
  Ok(authority)
}

///|
// One shared terminal boundary for the public observer and focused Owner tests.
// Neither the raw candidate nor arbitrary callback output can finalize state.
fn NativeLocalHostConnection::finalize_observed_run_state_candidate(
  self : NativeLocalHostConnection,
  publisher : NativeLocalPublisherBinding,
  authority : NativeLocalPolicyAuthority,
  candidate : @native_publication.NativeRunStateCandidate,
) -> Result[NativeLocalObservedRunState, NativeLocalObservedRunStateIssue] {
  let request = publisher.request
  if !physical_equal(publisher.authority.host, self) ||
    !physical_equal(authority.host, self) ||
    !(authority.purpose is ReadRunMaterials) ||
    authority.principal != publisher.authority.principal ||
    authority.connection != publisher.authority.connection ||
    authority.scope != publisher.authority.scope {
    return Err(ForeignOriginal)
  }
  guard candidate.original_client_request() is Some(original) else {
    return Err(OriginalUnavailable)
  }
  if @host.client_request_identity_relation(original, request) !=
    @host.SameRequest ||
    !candidate.matches_original_publisher(
      publisher.store,
      publisher.namespace_id,
      publisher.authority.scope,
      @publication.publication_contract_identity(publisher.definition),
      publisher.policy_cid,
      publisher.target_cid,
    ) {
    return Err(ForeignOriginal)
  }
  let (definition, manifest) = candidate.original_metadata()
  // All user callbacks have completed. Both predicates are the same trusted
  // Local Host's existing concrete current Owners, not another callback order.
  if !publisher.current() || !authority.current_for(self.journal, request) {
    return Err(AuthorizationDenied)
  }
  match candidate.require_original_store_current() {
    Ok(_) => ()
    Err(issue) => return Err(Candidate(issue))
  }
  let (projection, view, observed_at, max_wire, max_nodes, max_depth) = match
    candidate.projection_materials() {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let wire = match
    projection.observed_run_state_wire(
      view, observed_at, max_wire, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(@native_publication.State(issue)))
  }
  let receipt = match projection.view_contract(view, 3) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(Publication(Commit(issue))))
  }
  let accepted : NativeLocalObservedRunState = {
    host: self,
    publisher,
    read_authority: authority,
    request,
    definition,
    manifest,
    receipt,
    wire,
  }
  if !accepted.require_current_for(self, request) {
    return Err(AuthorizationDenied)
  }
  Ok(accepted)
}

///|
/// Export metadata only from the same accepted publication and independent
/// current RunRead. This does not grant payload delivery or acknowledge a file.
/// Managed installation/state paths remain excluded from ordinary exports.
pub fn NativeLocalObservedRunState::original_run_receipt_for_export(
  self : NativeLocalObservedRunState,
  path : String,
  parent : String,
  name : String,
) -> Result[@publication.PublicationContract, NativeLocalObservedRunStateIssue] {
  if !native_local_receipt_export_path(
      self.host.session.state_path,
      path,
      parent,
      name,
    ) {
    return Err(ForeignOriginal)
  }
  if !self.require_current_for(self.host, self.request) {
    return Err(AuthorizationDenied)
  }
  let capture = match self.publisher.authority.capture {
    Some(value) => value
    None => return Err(OriginalUnavailable)
  }
  match native_local_receipt_export_managed_path(capture, path) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !self.require_current_for(self.host, self.request) {
    return Err(AuthorizationDenied)
  }
  Ok(self.receipt)
}
