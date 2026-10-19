///|
// Current Policy authority is observed from this same captured adoption and
// entered Read. The original profile remains DATA, not an issuer or grant.
fn NativeLocalRunPolicyBinding::current_in_original_read(
  self : NativeLocalRunPolicyBinding,
  capture : NativeLocalJournalCapture,
  request : @host.ClientRequestIdentity?,
  new_submission : Bool,
) -> Bool {
  capture.with_current_adoption_material_in_original_read((host, material, _operations) => {
    if !physical_equal(host, self.host) ||
      !physical_equal(host.journal, self.host.journal) ||
      !(self.origin is Selected) ||
      (request is Some(original) &&
        @host.client_request_authority_scope_cid(original) != self.scope) {
      return Err(CustodyLost)
    }
    let body = match @host.client_local_adopted_authority_scope_body(
      material, host.database, self.principal, self.connection,
    ) {
      Ok(value) => value
      Err(issue) => return Err(local_current_material_issue(issue))
    }
    if !(local_adoption_digest(capture.crypto, body) is Ok(scope) && scope == self.scope) {
      return Err(CustodyLost)
    }
    for file in self.files {
      if !(capture.selected_configuration_in_original_read(file.name) is Ok(body) && body == file.body) {
        return Err(CustodyLost)
      }
    }
    let operations = if new_submission { ["submit", "publish", "read"] } else { ["read"] }
    for operation in operations {
      match @host.client_local_adopted_account_outcome(material, host.database, {
        principal: self.principal, connection: self.connection,
        resource: "run", operation,
      }) {
        Ok(@authorization.Allow(_)) => ()
        Ok(_) => return Err(Journal(AuthorizationDenied))
        Err(issue) => return Err(local_current_material_issue(issue))
      }
    }
    capture.check_current_in_original_read()
  }) is Ok(_)
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
    roles.run_file == run_file && selection.principal == principal &&
    selection.connection == connection else { return Err(CustodyLost) }
  let profile = match self.selected_configuration_in_original_read(profile_file) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !(local_adoption_digest(self.crypto, profile) is Ok(cid) && cid == roles.profile_cid) {
    return Err(CustodyLost)
  }
  host.bind_run_policy_profile_with_capture(
    self.crypto, principal, connection, profile_file, read_file,
    roles.run_file, roles.retention_file, roles.store_file, capture=Some(self),
  ).map_err(issue => Journal(issue))
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
  self.with_current_adoption_material_in_original_read((host, _material, operations) => {
    if !physical_equal(host, binding.host) { return Err(CustodyLost) }
    binding.prepare_submission_policy_with_operations(
      reference, preparation, request, observed_at, now,
      () => binding.current_in_original_read(self, Some(request), false),
      () => binding.current_in_original_read(self, Some(request), true),
      operations=Some(operations),
    ).map_err(issue => Journal(issue))
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
  self.with_current_adoption_material_in_original_read((host, _material, operations) => {
    if !physical_equal(host, binding.host) { return Err(CustodyLost) }
    binding.accept_submitted_run_with_operations(
      reference, preparation, request, compiled, definition, original, now,
      () => binding.current_in_original_read(self, Some(request), true),
      operations=Some(operations),
    ).map_err(issue => Journal(issue))
  })
}
