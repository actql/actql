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
  Ok({ host: self, crypto, file, selection, principal, connection, scope, })
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
  guard @values.timestamp_epoch_milliseconds(self.selection.expires_at)
    is Some(expiry) else {
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
