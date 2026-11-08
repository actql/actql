///|
// Current Policy authority is observed from this same captured adoption and
// entered Read. The original profile remains DATA, not an issuer or grant.
fn NativeLocalRunPolicyBinding::current_in_original_read(
  self : NativeLocalRunPolicyBinding,
  capture : NativeLocalJournalCapture,
  request : @host.ClientRequestIdentity?,
  new_submission : Bool,
) -> Bool {
  capture.with_current_adoption_material_in_original_read((
    host,
    material,
    _operations,
  ) => {
    if !physical_equal(host, self.host) ||
      !physical_equal(host.journal, self.host.journal) ||
      !(self.origin is Selected) ||
      (
        request is Some(original) &&
        @host.client_request_authority_scope_cid(original) != self.scope
      ) {
      return Err(CustodyLost)
    }
    if !(capture.operation_scope(
        host,
        material,
        self.principal,
        self.connection,
      )
      is Ok(scope) &&
      scope == self.scope) {
      return Err(CustodyLost)
    }
    for file in self.files {
      if !(capture.selected_configuration_in_original_read(file.name)
        is Ok(body) &&
        body == file.body) {
        return Err(CustodyLost)
      }
    }
    let operations = if new_submission {
      ["submit", "publish", "read"]
    } else {
      ["read"]
    }
    for operation in operations {
      match
        capture.operation_account(host, material, {
          principal: self.principal,
          connection: self.connection,
          resource: "run",
          operation,
        }) {
        Ok(@authorization.Allow(_)) => ()
        Ok(_) => return Err(Journal(AuthorizationDenied))
        Err(issue) => return Err(issue)
      }
    }
    capture.check_current_in_original_read()
  })
  is Ok(_)
}

///|
/// Bind only explicitly selected profile/role originals under this capture's
/// current Read. Missing legacy roles remain unavailable; no upgrade or new
/// Policy is issued by this observation.
pub fn NativeLocalJournalCapture::bind_run_policy_profile_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  profile_file : String,
  read_file : String,
  run_file : String,
) -> Result[NativeLocalRunPolicyBinding, NativeLocalAdoptionIssue] {
  match self.check_current_in_original_read() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.opening is JournalAcquired(host) else { return Err(CustodyLost) }
  let read = match self.selected_configuration_in_original_read(read_file) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let wire = @utf8.decode(read) catch { _ => return Err(Encoding) }
  let selection = match admit_native_local_read_selection(wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard selection.expiry is AcceptedRunProfile(roles) &&
    roles.run_file == run_file &&
    selection.principal == principal &&
    selection.connection == connection else {
    return Err(CustodyLost)
  }
  let profile = match
    self.selected_configuration_in_original_read(profile_file) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !(host.session.settings.files
    .iter()
    .find_first(file => file.name == profile_file)
    is Some(original) &&
    original.body == profile &&
    original.content_cid == roles.profile_cid) {
    return Err(CustodyLost)
  }
  host
  .bind_run_policy_profile_with_capture(
    self.crypto,
    principal,
    connection,
    profile_file,
    read_file,
    roles.run_file,
    roles.retention_file,
    roles.store_file,
    capture=Some(self),
  )
  .map_err(issue => Journal(issue))
}

///|
/// Reuse the existing lookup/first-issuance transaction with its actual
/// original Read/SQL exchange. Accepted lifetimes are never resampled.
pub fn NativeLocalJournalCapture::prepare_run_policy_in_original_read(
  self : NativeLocalJournalCapture,
  binding : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  observed_at : String,
  now : Double,
) -> Result[NativeLocalRunPolicyPreparation, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    if !physical_equal(host, binding.host) {
      return Err(CustodyLost)
    }
    binding
    .prepare_submission_policy_with_operations(
      reference,
      preparation,
      request,
      observed_at,
      now,
      () => binding.current_in_original_read(self, Some(request), false),
      () => binding.current_in_original_read(self, Some(request), true),
      operations=Some(operations),
    )
    .map_err(issue => Journal(issue))
  })
}

///|
/// Accept only the original checked Program and exact issued Policy packet.
/// Routing does not issue authority, dispatch work or replace an unknown Run.
pub fn NativeLocalJournalCapture::accept_policy_run_in_original_read(
  self : NativeLocalJournalCapture,
  binding : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  original : @host.ClientLocalRunPolicyOriginal,
  now : Double,
) -> Result[NativeClientSubmittedIntentRecord, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    if !physical_equal(host, binding.host) {
      return Err(CustodyLost)
    }
    binding
    .accept_submitted_run_with_operations(
      reference,
      preparation,
      request,
      compiled,
      definition,
      original,
      now,
      () => binding.current_in_original_read(self, Some(request), true),
      operations=Some(operations),
    )
    .map_err(issue => Journal(issue))
  })
}

///|
/// Bind the original candidate packet through its existing Policy Owner and
/// accept it under this capture. This is not another issuance or dispatch.
pub fn NativeLocalJournalCapture::accept_issued_policy_run_in_original_read(
  self : NativeLocalJournalCapture,
  binding : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  issued_at : String,
  now : Double,
) -> Result[NativeClientSubmittedIntentRecord, NativeLocalAdoptionIssue] {
  let original = match
    binding.issued_policy_original(
      reference, request, definition, retention, issued_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  self.accept_policy_run_in_original_read(
    binding, reference, preparation, request, compiled, definition, original, now,
  )
}

///|
/// Restore only the saved original Policy packet under current read authority.
/// Missing custody never becomes a fresh issuance candidate.
pub fn NativeLocalJournalCapture::lookup_run_policy_in_original_read(
  self : NativeLocalJournalCapture,
  binding : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
) -> Result[@host.ClientLocalRunPolicyOriginal, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    if !physical_equal(host, binding.host) {
      return Err(CustodyLost)
    }
    binding
    .lookup_submitted_run_policy_with_operations(
      reference,
      request,
      now,
      () => binding.current_in_original_read(self, Some(request), false),
      operations=Some(operations),
    )
    .map_err(issue => Journal(issue))
  })
}

///|
/// Bind the already selected finite Policy to the SAME first Effect originals.
/// This uses the existing acceptance transaction and preserves its inner
/// material result separately from the captured Read's return/current result.
pub fn NativeLocalJournalCapture::accept_issued_effect_policy_run_in_original_read(
  self : NativeLocalJournalCapture,
  binding : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : @host.ClientEffectIssuedNormalizationMaterials,
  retention : @publication.PublicationContract,
  issued_at : String,
  now : Double,
) -> Result[
  Result[
    NativeClientSubmittedIntentRecord,
    NativeClientSubmittedEffectMaterialsIssue,
  ],
  NativeLocalAdoptionIssue,
] {
  let original = match
    binding.issued_policy_original(
      reference, request, definition, retention, issued_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  self.accept_submitted_effect_material_original_in_original_read(
    binding.principal,
    binding.connection,
    binding.scope,
    reference,
    preparation,
    request,
    allowed,
    definition,
    issued,
    now,
    local_policy=Some((binding, original)),
  )
}
