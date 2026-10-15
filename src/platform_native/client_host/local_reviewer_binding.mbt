///|
pub(all) enum NativeLocalEffectReviewerBindingIssue {
  ReviewerUnavailable
  ReviewerSelection(NativeLocalEffectReviewerIssue)
  ReviewerOriginal(NativeClientOriginalCheckpointLookupIssue)
  ReviewerAuthentication(@effect_resolution.NativeResidentEffectResolutionIssue)
  ReviewerJournal(NativeClientRunJournalIssue)
}

///|
// Original Client read and configured Reviewer resolve are distinct roles.
// Only this adopted Host assembly constructs the physical/current binding.
struct NativeLocalEffectReviewerBinding {
  host : NativeLocalHostConnection
  crypto : @crypto.Library
  principal : String
  connection : String
  reference : NativeClientSubmissionReference
  request : @host.ClientRequestIdentity
  original : NativeClientOriginalCheckpointMetadata
  approval_scope : @resident.ResidentOriginalEffectApprovalScope
  installed : NativeLocalInstalledEffectReviewer
  now : () -> Double
}

///|
/// The selected registration is protected by original Host adoption custody.
/// This adapter view owns no registry, permission cache or execution state.
struct NativeLocalInstalledEffectReviewer {
  host : NativeLocalHostConnection
  file : String
  original_bytes : Bytes
  reviewer : NativeLocalEffectReviewerSelection
}

///|
/// Explicitly select one already-adopted original. No file means no Reviewer;
/// issuer installation and submit permission never enable this registration.
pub fn NativeLocalHostConnection::install_effect_reviewer(
  self : NativeLocalHostConnection,
  configuration_file? : String? = None,
) -> Result[
  NativeLocalInstalledEffectReviewer,
  NativeLocalEffectReviewerBindingIssue,
] {
  guard configuration_file is Some(file) &&
    self.session.settings.files.length() <= 8 else {
    return Err(ReviewerUnavailable)
  }
  let bytes = match self.selected_configuration(file) {
    Ok(value) => value
    Err(_) => return Err(ReviewerUnavailable)
  }
  let wire = @utf8.decode(bytes) catch {
    _ => return Err(ReviewerSelection(InvalidReviewerSelection))
  }
  let reviewer = match admit_native_local_effect_reviewer_selection(wire) {
    Ok(value) if value.enabled => value
    Ok(_) => return Err(ReviewerUnavailable)
    Err(issue) => return Err(ReviewerSelection(issue))
  }
  let value : NativeLocalInstalledEffectReviewer = {
    host: self,
    file,
    original_bytes: bytes,
    reviewer,
  }
  if !value.current() {
    return Err(ReviewerUnavailable)
  }
  Ok(value)
}

///|
fn NativeLocalInstalledEffectReviewer::current(
  self : NativeLocalInstalledEffectReviewer,
) -> Bool {
  if !self.reviewer.enabled ||
    !(self.host.selected_configuration(self.file) is Ok(bytes) &&
    bytes == self.original_bytes) {
    return false
  }
  self.host.authorize({
    principal: self.reviewer.principal,
    connection: self.reviewer.connection,
    resource: "run",
    operation: "resolve",
  })
  is Ok(@authorization.Allow(_))
}

///|
/// Keep the verified current registration with the authentication. A caller
/// cannot construct an approval from configuration or copy a public scope CID.
struct NativeLocalAuthenticatedEffectReviewer {
  binding : NativeLocalEffectReviewerBinding
  authentication : @checkpoint.HostAuthentication
  registration : @effect_resolution.NativeEffectReviewerRegistration
}

///|
/// An explicit selected original only. The CLI selects at most six installation
/// files; configuration and Check Environment use the Host's eight-file bound.
/// None never discovers or enables a Reviewer. This
/// issues no Resolution, Host attestation, resume claim or credential.
pub fn NativeLocalHostConnection::bind_effect_reviewer(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  approval_scope : @resident.ResidentOriginalEffectApprovalScope,
  now : () -> Double,
  configuration_file? : String? = None,
) -> Result[
  NativeLocalEffectReviewerBinding,
  NativeLocalEffectReviewerBindingIssue,
] {
  let installed = match self.install_effect_reviewer(configuration_file~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original = match
    self.lookup_submitted_checkpoint_metadata(
      crypto,
      principal,
      connection,
      reference,
      request,
      now(),
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(ReviewerUnavailable)
    Err(issue) => return Err(ReviewerOriginal(issue))
  }
  let binding : NativeLocalEffectReviewerBinding = {
    host: self,
    crypto,
    principal,
    connection,
    reference,
    request,
    original,
    approval_scope,
    installed,
    now,
  }
  match binding.read_current(binding.selected(), installed.reviewer.key_id) {
    Some(_) => Ok(binding)
    None => Err(ReviewerUnavailable)
  }
}

///|
fn NativeLocalEffectReviewerBinding::selected(
  self : NativeLocalEffectReviewerBinding,
) -> @effect_resolution.NativeEffectReviewerSelection {
  {
    principal_id: self.installed.reviewer.principal,
    checkpoint_cid: self.original.checkpoint_cid,
  }
}

///|
fn NativeLocalEffectReviewerBinding::original_current(
  self : NativeLocalEffectReviewerBinding,
) -> Bool {
  match
    self.host.lookup_submitted_checkpoint_metadata(
      self.crypto,
      self.principal,
      self.connection,
      self.reference,
      self.request,
      (self.now)(),
    ) {
    Ok(Some(value)) =>
      value.checkpoint_cid == self.original.checkpoint_cid &&
      value.run_definition_cid == self.original.run_definition_cid
    _ => false
  }
}

///|
fn NativeLocalEffectReviewerBinding::read_current(
  self : NativeLocalEffectReviewerBinding,
  selected : @effect_resolution.NativeEffectReviewerSelection,
  key_id : String,
) -> @effect_resolution.NativeEffectReviewerRegistration? {
  if selected != self.selected() ||
    key_id != self.installed.reviewer.key_id ||
    !self.installed.current() ||
    !self.original_current() {
    return None
  }
  let context = match
    self.host.authority_scope_cid(
      self.installed.reviewer.principal,
      self.installed.reviewer.connection,
      self.crypto,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  let policy = match self.host.configuration() {
    Ok(value) => value.configuration_cid()
    Err(_) => return None
  }
  let scope = match
    self.approval_scope.current_for(
      self.request,
      self.original.run_definition_cid,
      self.original.checkpoint_cid,
    ) {
    Some(value) if value ==
      @host.client_request_authority_scope_cid(self.request) => value
    _ => return None
  }
  if !self.original_current() ||
    !self.installed.current() ||
    self.host.check_binding() is Err(_) {
    return None
  }
  Some({
    selection: selected,
    key_id: self.installed.reviewer.key_id,
    reviewer_id: self.installed.reviewer.reviewer_id,
    public_key_pem: self.installed.reviewer.public_key_pem,
    approval_authority_scope_cid: scope,
    authority_context_cid: context,
    policy_cid: policy,
  })
}

///|
/// Use the existing Native signature Owner. Its before/after callbacks read
/// current adopted Host and independent Reviewer authority, not a fake Site.
pub fn NativeLocalEffectReviewerBinding::authenticate_resolution(
  self : NativeLocalEffectReviewerBinding,
  resolution_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  NativeLocalAuthenticatedEffectReviewer,
  NativeLocalEffectReviewerBindingIssue,
] {
  let selected = self.selected()
  let registration = match
    self.read_current(selected, self.installed.reviewer.key_id) {
    Some(value) => value
    None => return Err(ReviewerUnavailable)
  }
  let authentication = match
    @effect_resolution.authenticate_native_effect_reviewer(
      {
        crypto: self.crypto,
        current_site: () => self.host.check_binding() is Ok(_),
        read_current: (selection, key) => self.read_current(selection, key),
      },
      selected,
      resolution_wire,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ReviewerAuthentication(issue))
  }
  if self.read_current(selected, registration.key_id) != Some(registration) {
    return Err(ReviewerUnavailable)
  }
  Ok({ binding: self, authentication, registration, })
}

///|
/// Signature authentication is only one input to the existing Resolution
/// Owner. Actual Host attestation and all common admission/commit checks still
/// apply; current Reviewer and original Client read are rechecked at admission.
/// This remains private until the actual Host attestation installation supplies
/// its trusted keys. Public callers cannot choose Host attestation authority.
// Operational admission still requires the original authenticated Host
// attestation supplier; exporting this private seam would bypass that boundary.
#warnings("-unused_value")
fn NativeLocalAuthenticatedEffectReviewer::admit_original_resolution(
  self : NativeLocalAuthenticatedEffectReviewer,
  verified_wire : String,
  host_authorities : Array[@effect_resolution.NativeEffectHostAuthority],
  now : () -> String,
) -> Result[NativeClientRunRecord, NativeLocalEffectReviewerBindingIssue] {
  let binding = self.binding
  let current = () => {
    binding.read_current(self.registration.selection, self.registration.key_id) ==
    Some(self.registration)
  }
  if !current() {
    return Err(ReviewerUnavailable)
  }
  binding.host.journal
  .resolve_effect_checkpoint(
    binding.request,
    binding.crypto,
    verified_wire,
    self.authentication,
    [
      {
        key_id: self.registration.key_id,
        reviewer_id: self.registration.reviewer_id,
      },
    ],
    host_authorities,
    current,
    now,
  )
  .map_err(issue => ReviewerJournal(issue))
}
