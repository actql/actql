///|
pub(all) enum NativeLocalReadBindingIssue {
  Selection(NativeLocalReadPolicyIssue)
  Adoption(NativeLocalAdoptionIssue)
  Journal(NativeClientRunJournalIssue)
  AuthorizationDenied
  Disabled
  SelectionMismatch
  InvalidObservationTime
  PolicyExpired
  PolicyNotSelected
}

///|
// Constructed only from an original selected file in the real adopted Host.
// Parsing a selection or possessing this binding grants no payload bytes.
struct NativeLocalReadPolicyBinding {
  host : NativeLocalHostConnection
  crypto : @crypto.Library
  file : NativeLocalSelectedFile
  selection : NativeLocalReadSelection
  principal : String
  connection : String
  scope : String
  expires_at : String
  run_policy_original : (
    NativeClientSubmissionReference,
    @host.ClientRequestIdentity,
    Bytes,
  )?
}

///|
pub fn NativeLocalHostConnection::bind_result_read_policy(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  file_name : String,
  principal : String,
  connection : String,
) -> Result[NativeLocalReadPolicyBinding, NativeLocalReadBindingIssue] {
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  guard self.session.settings.files
    .iter()
    .find_first(file => file.name == file_name)
    is Some(file) else {
    return Err(SelectionMismatch)
  }
  let text = @utf8.decode(file.body) catch {
    _ => return Err(Selection(InvalidOriginal))
  }
  let selection = match admit_native_local_read_selection(text) {
    Ok(value) => value
    Err(issue) => return Err(Selection(issue))
  }
  if selection.principal != principal || selection.connection != connection {
    return Err(SelectionMismatch)
  }
  guard selection.expiry is Absolute(expires_at) else {
    return Err(SelectionMismatch)
  }
  Ok({
    host: self,
    crypto,
    file,
    selection,
    principal,
    connection,
    scope,
    expires_at,
    run_policy_original: None,
  })
}

///|
/// An explicitly selected finite read mode requires its original accepted Run
/// packet. The current adoption/profile/read selection is still checked by the
/// Host; a caller-provided lifetime or copied packet cannot construct custody.
pub fn NativeLocalHostConnection::bind_result_read_policy_for_run(
  self : NativeLocalHostConnection,
  policy : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
) -> Result[NativeLocalReadPolicyBinding, NativeLocalReadBindingIssue] {
  if !physical_equal(self, policy.host) {
    return Err(SelectionMismatch)
  }
  let file = policy.files[1]
  let text = @utf8.decode(file.body) catch {
    _ => return Err(Selection(InvalidOriginal))
  }
  let selection = match admit_native_local_read_selection(text) {
    Ok(value) => value
    Err(issue) => return Err(Selection(issue))
  }
  guard selection.expiry is AcceptedRunProfile(roles) &&
    roles.profile_cid ==
    @host.client_local_run_policy_profile_cid(policy.profile) &&
    roles.run_file == policy.files[2].name &&
    roles.retention_file == policy.files[3].name &&
    roles.store_file == policy.files[4].name &&
    selection.principal == policy.principal &&
    selection.connection == policy.connection else {
    return Err(SelectionMismatch)
  }
  let original = match
    policy.lookup_submitted_run_policy(reference, request, now) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let expires_at = @host.client_local_run_policy_original_read_expires_at(
    original,
  )
  if !read_policy_timestamp(expires_at) {
    return Err(Selection(InvalidOriginal))
  }
  let binding : NativeLocalReadPolicyBinding = {
    host: self,
    crypto: policy.crypto,
    file,
    selection,
    principal: policy.principal,
    connection: policy.connection,
    scope: policy.scope,
    expires_at,
    run_policy_original: Some(
      (
        reference,
        request,
        @host.client_local_run_policy_original_body(original),
      ),
    ),
  }
  binding.require_current().map(_ => binding)
}

///|
fn NativeLocalReadPolicyBinding::require_current(
  self : NativeLocalReadPolicyBinding,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  let scope = match
    self.host.authority_scope_cid(self.principal, self.connection, self.crypto) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  if scope != self.scope {
    return Err(AuthorizationDenied)
  }
  // check_binding above validates exact retained membership and original
  // physical generation. A current replacement cannot repair this binding.
  let current = match self.host.selected_configuration(self.file.name) {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  if current != self.file.body {
    return Err(SelectionMismatch)
  }
  if self.run_policy_original is Some((reference, request, body)) {
    guard self.host.journal.retained(request) is Ok(Some(run)) &&
      run.local_run_policy_originals is Some(wire) &&
      @utf8.encode(wire) == body &&
      self.host.journal.retained_submission(reference) is Ok(Some(submission)) &&
      submission.run_admission is Some(admission) &&
      @host.client_request_identity_relation(admission.request, request) ==
      @host.SameRequest &&
      admission.run_definition_cid ==
      @publication.publication_contract_identity(run.definition) else {
      return Err(Journal(CustodyLost))
    }
  }
  Ok(())
}

///|
fn NativeLocalReadPolicyBinding::require_request(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.run_policy_original is Some((_, bound, _)) &&
    @host.client_request_identity_relation(bound, original) != @host.SameRequest {
    return Err(SelectionMismatch)
  }
  if !self.selection.enabled {
    return Err(Disabled)
  }
  if facts.request.principal_id != self.principal ||
    facts.request.authority_scope_cid != self.scope ||
    @host.client_request_authority_scope_cid(original) != self.scope {
    return Err(AuthorizationDenied)
  }
  if !self.selection.result_names.contains(facts.request.result_name) ||
    !self.selection.formats.contains(facts.request.format) ||
    facts.request.purpose != self.selection.purpose ||
    facts.request.attempt_id.is_empty() {
    return Err(SelectionMismatch)
  }
  let observed = match @values.timestamp_epoch_milliseconds(facts.observed_at) {
    Some(value) => value
    None => return Err(InvalidObservationTime)
  }
  guard @values.timestamp_epoch_milliseconds(self.expires_at) is Some(expiry) else {
    return Err(Selection(InvalidOriginal))
  }
  if observed >= expiry {
    return Err(PolicyExpired)
  }
  match
    native_local_policy_authority(
      self.host,
      self.crypto,
      self.principal,
      self.connection,
      original,
      Some(facts.request.result_name),
    ) {
    Ok(_) => Ok(())
    Err(issue) => Err(Journal(issue))
  }
}

///|
/// Current Account read tuples, explicit stdout selection and expiry are
/// independent of submit and Source Policy classification. The committed
/// Artifact's actual Policy must also be explicitly selected and retained.
/// This pure resolution creates no grant, payload or control revision.
pub fn NativeLocalReadPolicyBinding::resolve_policy_original(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  facts : @result_access.NativeResultReadFacts,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeLocalReadBindingIssue,
] {
  match self.require_request(original, facts) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let body = match
    self.host.resolve_result_policy_original(
      self.crypto,
      self.principal,
      self.connection,
      original,
      store,
      facts,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if !self.selection.data_policy_cids.contains(
      @publication.captured_effect_dependency_body_cid(body),
    ) {
    return Err(PolicyNotSelected)
  }
  match self.require_request(original, facts) {
    Ok(_) => Ok(body)
    Err(issue) => Err(issue)
  }
}
