///|
// The existing adopted file and Host retain the physical original. This
// private selection is not a Policy issuer, permission or replacement custody.
priv struct NativeLocalEffectValuesPolicySelection {
  host : NativeLocalHostConnection
  file : NativeLocalSelectedFile
}

///|
fn NativeLocalEffectValuesPolicySelection::current(
  self : NativeLocalEffectValuesPolicySelection,
) -> Bool {
  self.host.selected_configuration(self.file.name) is Ok(bytes) &&
  bytes == self.file.body
}

///|
fn native_effect_values_policy_body(
  wire : String,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientRunJournalIssue,
] {
  let bodies = match read_run_policy_originals(wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard bodies.length() == 1 else { return Err(CustodyLost) }
  let body = bodies[0]
  if @publication.captured_effect_dependency_body_kind(body) != "data_policy" ||
    @host.admit_source_free_result_policy_body(
      @publication.captured_effect_dependency_body_cid(body),
      @publication.captured_effect_dependency_body_json(body),
      8192,
      512,
      8,
    )
    is Err(_) {
    return Err(CustodyLost)
  }
  Ok(body)
}

///|
// Selection is first-accept only. An already accepted request returns its
// saved packet before touching a candidate filename or constructing a policy.
// The final transaction rechecks the same original and refuses lost custody.
fn NativeLocalHostConnection::select_effect_values_policy_originals(
  self : NativeLocalHostConnection,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  run_file : String,
) -> Result[
  (String, NativeLocalEffectValuesPolicySelection?),
  NativeClientRunJournalIssue,
] {
  let original = match self.journal.retained_submission(reference) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  if original.run_admission is Some(admission) {
    if @host.client_request_identity_relation(admission.request, request) !=
      @host.SameRequest ||
      admission.run_definition_cid !=
      @publication.publication_contract_identity(definition) {
      return Err(ChangedIntent)
    }
    let record = match self.journal.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    guard record.publication_policy_originals is Some(wire) &&
      @publication.publication_contract_identity(record.definition) ==
      admission.run_definition_cid else {
      return Err(CustodyLost)
    }
    match native_effect_values_policy_body(wire) {
      Ok(_) => Ok((wire, None))
      Err(issue) => Err(issue)
    }
  } else {
    let file = match local_run_policy_selected(self, run_file) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let body = local_run_policy_source_free_original(
      local_run_policy_run_fields(file.body),
    ) catch {
      LocalReadPolicyStop(_) => return Err(CustodyLost)
    }
    let wire = match @host.encode_client_source_free_policy_originals(body) {
      Ok(value) => value
      Err(issue) => return Err(policy_originals_issue(issue))
    }
    let selection : NativeLocalEffectValuesPolicySelection = {
      host: self,
      file,
    }
    if !selection.current() {
      return Err(AuthorizationDenied)
    }
    Ok((wire, Some(selection)))
  }
}

///|
/// Read only the original accepted Effect packet's source-free policy. Current
/// RunRead, exact Submission/request/Run and original packet bytes are checked
/// again around the existing journal transaction. No current run.json is used
/// to repair a missing packet, and no Result payload or grant is opened.
pub fn NativeLocalHostConnection::lookup_submitted_effect_values_policy_original(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  let original = match
    self.lookup_submitted_effect_material_original(
      crypto, principal, connection, reference, request, now,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      ReadRunMaterials,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if !authority.current_for(self.journal, request) {
    return Err(Journal(AuthorizationDenied))
  }
  self.journal
  .transaction(() => {
    if !authority.current_for(self.journal, request) {
      return Err(AuthorizationDenied)
    }
    let record = match self.journal.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    let submission = match self.journal.retained_submission(reference) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    guard submission.run_admission is Some(admission) &&
      @host.client_request_identity_relation(admission.request, request) ==
      @host.SameRequest &&
      admission.run_definition_cid ==
      @publication.publication_contract_identity(original.definition) else {
      return Err(CustodyLost)
    }
    guard record.effect_material_originals is Some(packet_wire) &&
      read_effect_material_original_packet(packet_wire) is Ok(packet) &&
      packet.intent_cid == @host.client_submitted_intent_cid(submission.intent) &&
      packet.submission_reference == reference.wire &&
      packet.request_scope_cid == @host.client_request_scope_cid(request) &&
      packet.run_definition_cid == admission.run_definition_cid &&
      packet.materials_cid == original.materials_cid &&
      packet.materials_wire == original.materials_wire &&
      @publication.publication_contract_identity(record.definition) ==
      @publication.publication_contract_identity(original.definition) else {
      return Err(CustodyLost)
    }
    guard record.publication_policy_originals is Some(wire) else {
      return Err(PublicationPolicy(@checked.MissingDependency))
    }
    let body = match native_effect_values_policy_body(wire) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !authority.current_for(self.journal, request) {
      return Err(AuthorizationDenied)
    }
    Ok(body)
  })
  .map_err(issue => Journal(issue))
}
