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
  MaterialUnavailable
  OriginalRead(NativeLocalReadBindingIssue?, NativeLocalAdoptionIssue)
  SubmittedResult(NativeClientSubmittedResultIssue)
}

///|
// Constructed only from an original selected file in the real adopted Host.
// Parsing a selection or possessing this binding grants no payload bytes.
struct NativeLocalReadPolicyBinding {
  host : NativeLocalHostConnection
  capture : NativeLocalJournalCapture?
  crypto : @crypto.Library
  file : NativeLocalSelectedFile
  selection : NativeLocalReadSelection
  principal : String
  connection : String
  scope : String
  expires_at : String
  selection_cid : String
  mut material_receiver : @result_access.NativeResultMaterialReceiver?
  mut material_original : NativeLocalReadMaterialOriginal?
  upgrade_packet : Bytes?
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
  if selection.sink != Stdout {
    return Err(MaterialUnavailable)
  }
  guard selection.expiry is Absolute(expires_at) else {
    return Err(SelectionMismatch)
  }
  Ok({
    host: self,
    capture: None,
    crypto,
    file,
    selection,
    principal,
    connection,
    scope,
    expires_at,
    selection_cid: file.content_cid,
    material_receiver: None,
    material_original: None,
    upgrade_packet: None,
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
  self.bind_result_read_policy_for_run_with_capture(
    policy, reference, request, now,
  )
}

///|
fn NativeLocalHostConnection::bind_result_read_policy_for_run_with_capture(
  self : NativeLocalHostConnection,
  policy : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
  capture? : NativeLocalJournalCapture? = None,
  material? : @result_access.NativeResultMaterialReceiver? = None,
  material_file? : String? = None,
) -> Result[NativeLocalReadPolicyBinding, NativeLocalReadBindingIssue] {
  if !physical_equal(self, policy.host) {
    return Err(SelectionMismatch)
  }
  let file = match material_file {
    None => policy.read_file
    Some(name) => {
      if capture is None ||
        !(policy.origin is Selected) ||
        name == policy.read_file.name {
        return Err(SelectionMismatch)
      }
      guard self.session.settings.files
        .iter()
        .find_first(file => file.name == name)
        is Some(file) &&
        capture is Some(current) &&
        current.selected_configuration_in_original_read(name) is Ok(body) &&
        body == file.body else {
        return Err(SelectionMismatch)
      }
      file
    }
  }
  let text = match policy.origin {
    Selected =>
      @utf8.decode(file.body) catch {
        _ => return Err(Selection(InvalidOriginal))
      }
    Upgraded(_, wire) => wire
  }
  let selection = match admit_native_local_read_selection(text) {
    Ok(value) => value
    Err(issue) => return Err(Selection(issue))
  }
  let material_original = match (selection.sink, material) {
    (Stdout, None) => None
    (Material, None) if material_file is Some(_) && capture is Some(_) => None
    (Material, Some(receiver)) => {
      if !receiver.covers_read_limits(selection.max_bytes, selection.max_uses) {
        return Err(MaterialUnavailable)
      }
      let identity = receiver.identity()
      Some({
        receiver_cid: identity.receiver_cid,
        result_schema_cid: identity.result_schema_cid,
        ordering_evidence_cid: identity.ordering_evidence_cid,
      })
    }
    _ => return Err(MaterialUnavailable)
  }
  guard selection.expiry is AcceptedRunProfile(roles) &&
    roles.profile_cid ==
    @host.client_local_run_policy_profile_cid(policy.profile) &&
    roles.run_file == policy.run_file.name &&
    roles.retention_file == policy.retention_file.name &&
    roles.store_file == policy.store_file.name &&
    selection.principal == policy.principal &&
    selection.connection == policy.connection else {
    return Err(SelectionMismatch)
  }
  let original = match capture {
    None =>
      match policy.lookup_submitted_run_policy(reference, request, now) {
        Ok(value) => value
        Err(issue) => return Err(Journal(issue))
      }
    Some(original) => {
      if !(policy.origin is Selected) ||
        !policy.current_in_original_read(original, Some(request), false) {
        return Err(SelectionMismatch)
      }
      match
        original.lookup_run_policy_in_original_read(
          policy, reference, request, now,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Adoption(issue))
      }
    }
  }
  let expires_at = @host.client_local_run_policy_original_read_expires_at(
    original,
  )
  if !read_policy_timestamp(expires_at) {
    return Err(Selection(InvalidOriginal))
  }
  let binding : NativeLocalReadPolicyBinding = {
    host: self,
    capture,
    crypto: policy.crypto,
    file,
    selection,
    principal: policy.principal,
    connection: policy.connection,
    scope: policy.scope,
    expires_at,
    selection_cid: if material_file is Some(_) {
      file.content_cid
    } else {
      policy.read_selection_cid
    },
    material_receiver: material,
    material_original,
    upgrade_packet: match policy.origin {
      Selected => None
      Upgraded(packet, _) => Some(packet)
    },
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
  match self.capture {
    None => self.require_current_with_reads()
    Some(capture) =>
      read_binding_in_original_read(capture, (host, operations) => {
        if !physical_equal(host, self.host) {
          return Err(SelectionMismatch)
        }
        self.require_current_with_reads(reads=Some(operations.reads))
      })
  }
}

///|
fn NativeLocalReadPolicyBinding::require_current_with_reads(
  self : NativeLocalReadPolicyBinding,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  let observed_scope = match self.capture {
    None =>
      self.host.authority_scope_cid(
        self.principal,
        self.connection,
        self.crypto,
      )
    Some(capture) =>
      capture.authority_scope_cid_in_original_read(
        self.principal,
        self.connection,
      )
  }
  let scope = match observed_scope {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  if scope != self.scope {
    return Err(AuthorizationDenied)
  }
  // check_binding above validates exact retained membership and original
  // physical generation. A current replacement cannot repair this binding.
  let selected = match self.capture {
    None => self.host.selected_configuration(self.file.name)
    Some(capture) =>
      capture.selected_configuration_in_original_read(self.file.name)
  }
  let current = match selected {
    Ok(value) => value
    Err(issue) => return Err(Adoption(issue))
  }
  if current != self.file.body {
    return Err(SelectionMismatch)
  }
  if self.upgrade_packet is Some(packet) {
    // The captured constructor accepts selected finite originals only. The
    // separate legacy/upgraded installation route retains its own custody.
    if self.capture is Some(_) {
      return Err(SelectionMismatch)
    }
    guard self.host.database.read(
        "client_local_installation_originals", local_policy_upgrade_key,
      )
      is Ok(row) &&
      row.revision == 0L &&
      row.body == packet else {
      return Err(Journal(CustodyLost))
    }
    if self.host.with_installation_custody(() => Ok(())) is Err(_) {
      return Err(Journal(CustodyLost))
    }
  }
  if self.run_policy_original is Some((reference, request, body)) {
    guard self.host.journal.retained(request, reads~) is Ok(Some(run)) &&
      run.local_run_policy_originals is Some(wire) &&
      @utf8.encode(wire) == body &&
      self.host.journal.retained_submission(reference, reads~)
      is Ok(Some(submission)) &&
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
  if self.selection.sink == Material {
    guard self.material_receiver is Some(receiver) &&
      self.material_original is Some(original) &&
      receiver.matches_facts(facts) &&
      receiver.identity().receiver_cid == original.receiver_cid &&
      receiver.identity().result_schema_cid == original.result_schema_cid &&
      receiver.identity().ordering_evidence_cid ==
      original.ordering_evidence_cid else {
      return Err(MaterialUnavailable)
    }
  }
  self.require_request_selection(original, facts)
}

///|
// Shared current/Account/selection admission before material workspace and
// again with its actual receiver before any payload read or delivery.
fn NativeLocalReadPolicyBinding::require_request_selection(
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
  if self.selection.expiry is Absolute(_) {
    match self.host.require_original_legacy_policy(original) {
      Ok(_) => ()
      Err(issue) => return Err(Journal(issue))
    }
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
    native_local_policy_authority_for(
      self.host,
      self.crypto,
      self.principal,
      self.connection,
      original,
      ReadResultPolicy(facts.request.result_name),
      capture=self.capture,
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
  let body = match self.capture {
    None =>
      match
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
    Some(capture) =>
      match
        capture.resolve_result_policy_original_in_original_read(
          self.principal,
          self.connection,
          original,
          store,
          facts,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Adoption(issue))
      }
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
