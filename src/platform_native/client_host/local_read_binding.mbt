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
  FileOutputUnavailable
  FileOutput(@filesystem.NativeFilesystemIssue)
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
  mut file_destination : NativeLocalReadFileDestination?
  mut file_original : NativeLocalReadFileOriginal?
  mut file_store : @publication_store.Store?
  mut file_preparation : (
    @host.ClientRequestIdentity,
    @result_access.NativeResultAccessRequest,
  )?
  upgrade_packet : Bytes?
  run_policy_original : (
    NativeClientSubmissionReference,
    @host.ClientRequestIdentity,
    Bytes,
  )?
  // One resolved committed Result root in this existing binding. This is only
  // immutable correspondence, never a cached current Allow or read grant.
  mut result_policy_original : (
    @host.ClientRequestIdentity,
    @result_access.NativeResultReadFacts,
    String,
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
    file_destination: None,
    file_original: None,
    file_store: None,
    file_preparation: None,
    upgrade_packet: None,
    run_policy_original: None,
    result_policy_original: None,
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
  file_configuration? : String? = None,
) -> Result[NativeLocalReadPolicyBinding, NativeLocalReadBindingIssue] {
  if !physical_equal(self, policy.host) {
    return Err(SelectionMismatch)
  }
  if material_file is Some(_) && file_configuration is Some(_) {
    return Err(SelectionMismatch)
  }
  let independent_file = match material_file {
    Some(_) => material_file
    None => file_configuration
  }
  let file = match independent_file {
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
    (File, None) if file_configuration is Some(_) && capture is Some(_) => None
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
    selection_cid: if independent_file is Some(_) {
      file.content_cid
    } else {
      policy.read_selection_cid
    },
    material_receiver: material,
    material_original,
    file_destination: None,
    file_original: None,
    file_store: None,
    file_preparation: None,
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
    result_policy_original: None,
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
      read_binding_with_material_in_original_read(capture, (
        host,
        material,
        operations,
      ) => {
        if !physical_equal(host, self.host) {
          return Err(SelectionMismatch)
        }
        read_binding_in_journal_snapshot(host.journal, operations.reads, () => {
          self.require_current_in_snapshot(material, operations.reads)
        })
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
  let selected = match self.capture {
    None => self.host.selected_configuration(self.file.name)
    Some(capture) =>
      capture.selected_configuration_in_original_read(self.file.name)
  }
  self.require_current_with_facts(scope, selected, reads~)
}

///|
fn NativeLocalReadPolicyBinding::require_current_with_facts(
  self : NativeLocalReadPolicyBinding,
  scope : String,
  selected : Result[Bytes, NativeLocalAdoptionIssue],
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  if scope != self.scope {
    return Err(AuthorizationDenied)
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
  match self.require_receiver(facts) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.require_request_selection(original, facts)
}

///|
fn NativeLocalReadPolicyBinding::require_receiver(
  self : NativeLocalReadPolicyBinding,
  facts : @result_access.NativeResultReadFacts,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  if self.selection.sink == File {
    guard self.file_destination is Some(destination) &&
      self.file_original is Some(original) else {
      return Err(FileOutputUnavailable)
    }
    match destination.original_data() {
      Ok(actual) if actual == original => ()
      Ok(_) => return Err(FileOutputUnavailable)
      Err(issue) => return Err(FileOutput(issue))
    }
  }
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
  Ok(())
}

///|
// Shared current/Account/selection admission before material workspace and
// again with its actual receiver before any payload read or delivery.
fn NativeLocalReadPolicyBinding::require_request_selection(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  if self.capture is Some(capture) {
    return read_binding_with_material_in_original_read(capture, (
      host,
      material,
      operations,
    ) => {
      if !physical_equal(host, self.host) {
        return Err(SelectionMismatch)
      }
      read_binding_in_journal_snapshot(host.journal, operations.reads, () => {
        self.require_request_in_snapshot(
          original,
          facts,
          material,
          operations.reads,
        )
      })
    })
  }
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.require_request_constraints(original, facts) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
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
// Exact selection and time constraints are pure in a selected captured frame.
// The legacy expiry route still invokes its original policy custody check.
fn NativeLocalReadPolicyBinding::require_request_constraints(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
) -> Result[Unit, NativeLocalReadBindingIssue] {
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
  Ok(())
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
  self.resolve_policy_with_committed_result(original, store, facts, None)
}

///|
// A closed delivery caller already selected this typed observation from the
// same Store. It is reused only for this synchronous policy correspondence;
// Store custody, current permissions and every original reference still join.
fn NativeLocalReadPolicyBinding::resolve_policy_with_committed_result(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  facts : @result_access.NativeResultReadFacts,
  committed_result : @publication_store.NativeCommittedResult?,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeLocalReadBindingIssue,
] {
  self.result_policy_original = None
  if self.capture is Some(capture) {
    return self.resolve_policy_from_snapshot(
      capture,
      original,
      store,
      facts,
      committed_result~,
    )
  }
  match self.require_request(original, facts) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let body = match self.capture {
    None =>
      match
        self.host.resolve_result_policy_original_with_operations(
          self.crypto,
          self.principal,
          self.connection,
          original,
          store,
          facts,
          committed_result~,
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
  match self.retain_result_policy_original(original, facts, body) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.require_request(original, facts) {
    Ok(_) => Ok(body)
    Err(issue) => Err(issue)
  }
}

///|
// Called only after the existing trusted Store/first-packet resolver has
// matched the committed Result and selected its actual effective Policy root.
fn NativeLocalReadPolicyBinding::retain_result_policy_original(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  body : @publication.CapturedEffectDependencyBody,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  let cid = @publication.captured_effect_dependency_body_cid(body)
  match self.selection.policy {
    ExplicitPolicyCids(cids) =>
      if !cids.contains(cid) {
        return Err(PolicyNotSelected)
      }
    AcceptedRunPolicy => {
      guard self.run_policy_original is Some((_, bound, _)) &&
        @host.client_request_identity_relation(bound, original) ==
        @host.SameRequest else {
        return Err(SelectionMismatch)
      }
      self.result_policy_original = Some((original, facts, cid))
    }
  }
  Ok(())
}

///|
// Projection of an already-resolved root, with no callback or Store read.
// Literal selections preserve their original array and ceiling preimage.
fn NativeLocalReadPolicyBinding::selected_policy_cids(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  actual_policy_cid : String,
) -> Result[Array[String], NativeLocalReadBindingIssue] {
  match self.selection.policy {
    ExplicitPolicyCids(cids) =>
      if cids.contains(actual_policy_cid) {
        Ok(cids)
      } else {
        Err(PolicyNotSelected)
      }
    AcceptedRunPolicy => {
      guard self.run_policy_original is Some((_, run_request, _)) &&
        @host.client_request_identity_relation(run_request, original) ==
        @host.SameRequest &&
        self.result_policy_original is Some((bound, resolved, cid)) &&
        @host.client_request_identity_relation(bound, original) ==
        @host.SameRequest &&
        cid == actual_policy_cid &&
        local_read_file_same_request(resolved.request, facts.request) &&
        resolved.public_index_entry_cid == facts.public_index_entry_cid &&
        resolved.result_manifest_cid == facts.result_manifest_cid &&
        resolved.result_artifact_cid == facts.result_artifact_cid &&
        resolved.result_definition_cid == facts.result_definition_cid &&
        resolved.material_generation_cid == facts.material_generation_cid else {
        return Err(PolicyNotSelected)
      }
      Ok([cid])
    }
  }
}
