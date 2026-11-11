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
  approval_scope : NativeLocalOriginalEffectApprovalScope
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
  initial_original : NativeLocalInitialSigningOriginal?
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
    initial_original: None,
  }
  if !value.current() {
    return Err(ReviewerUnavailable)
  }
  Ok(value)
}

///|
// Same selected configuration/key projection only. This does not authorize a
// Reviewer. Closed terminal projections use it after their enclosing current
// read; each actual resolve entry still evaluates its own Account below.
fn NativeLocalInstalledEffectReviewer::configuration_current(
  self : NativeLocalInstalledEffectReviewer,
) -> Bool {
  if !self.reviewer.enabled {
    return false
  }
  let selected = match self.initial_original {
    Some(original) => original.selected_configuration(self.file)
    None => self.host.selected_configuration(self.file)
  }
  if !(selected is Ok(bytes) && bytes == self.original_bytes) {
    return false
  }
  match self.initial_original {
    None => ()
    Some(original) =>
      if !self.initial_reviewer_original_current(original) {
        return false
      }
  }
  true
}

///|
fn NativeLocalInstalledEffectReviewer::current(
  self : NativeLocalInstalledEffectReviewer,
) -> Bool {
  if !self.configuration_current() {
    return false
  }
  let tuple : @authorization.AccessTuple = {
    principal: self.reviewer.principal,
    connection: self.reviewer.connection,
    resource: "run",
    operation: "resolve",
  }
  let outcome = match self.initial_original {
    Some(original) => original.authorize(tuple)
    None => self.host.authorize(tuple)
  }
  outcome is Ok(@authorization.Allow(_))
}

///|
// Terminal fence only, after the binding's independent current/resolve and
// original approval-scope checks. No clock or user callback intervenes here.
// Reuse the SAME saved Read's material, never its Account outcome.
fn NativeLocalInstalledEffectReviewer::terminal_saved_host_current(
  self : NativeLocalInstalledEffectReviewer,
  host : NativeLocalHostConnection,
  capture : NativeLocalJournalCapture,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if !physical_equal(self.host, host) {
    return Err(CustodyLost)
  }
  if self.initial_original is Some(original) &&
    original.original_read is Some((actual_capture, _)) {
    if !physical_equal(original.host, host) ||
      !physical_equal(actual_capture, capture) {
      return Err(OriginalResourceScopePending)
    }
    // Actual entered Read/material/Library plus the unchanged SQLite fence,
    // physical DB generation and original lifetime. Expired/foreign Some
    // refuses; it never selects the full legacy path as a substitute.
    match original.check_initial_control_read_scope(host) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    return original.check_host_current()
  }
  // Configured and cold/legacy registrations retain their complete fence.
  host.check_binding()
}

///|
/// Keep the verified current registration with the authentication. A caller
/// cannot construct an approval from configuration or copy a public scope CID.
struct NativeLocalAuthenticatedEffectReviewer {
  binding : NativeLocalEffectReviewerBinding
  authentication : @checkpoint.HostAuthentication
  registration : @effect_resolution.NativeEffectReviewerRegistration
  resolution_wire : String
  limits : @checkpoint.WireLimits
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
  self.bind_selected_effect_reviewer(
    crypto,
    principal,
    connection,
    reference,
    request,
    ResidentApproval(approval_scope),
    now,
    installed,
  )
}

///|
// Both original registration routes use the same retained Checkpoint, Client
// read, paired-scope and terminal-current path. Registration does not issue a
// proof, a grant, a key-use claim or permission to apply a Resolution.
fn NativeLocalHostConnection::bind_selected_effect_reviewer(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  approval_scope : NativeLocalOriginalEffectApprovalScope,
  now : () -> Double,
  installed : NativeLocalInstalledEffectReviewer,
) -> Result[
  NativeLocalEffectReviewerBinding,
  NativeLocalEffectReviewerBindingIssue,
] {
  if !physical_equal(self, installed.host) || !installed.current() {
    return Err(ReviewerUnavailable)
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
  let now = (self.now)()
  if self.installed.initial_original is Some(original) &&
    original.original_read is Some(_) &&
    original.check_callback_current() is Err(_) {
    return false
  }
  if self.approval_scope is SavedApproval(saved) {
    // The clock is a callback; enter the actual current Read only AFTER it.
    // The same typed query route retains invalidation and SQL return duties.
    return match
      saved.capture.with_current_adoption_material_in_original_read((
        host,
        _material,
        operations,
      ) => {
        if !physical_equal(host, self.host) {
          return Err(CustodyLost)
        }
        Ok(
          host.lookup_submitted_checkpoint_metadata_with_operations(
            self.crypto,
            self.principal,
            self.connection,
            self.reference,
            self.request,
            now,
            operations=Some(operations),
            capture=Some(saved.capture),
          ),
        )
      }) {
      Ok(Ok(Some(value))) =>
        value.checkpoint_cid == self.original.checkpoint_cid &&
        value.run_definition_cid == self.original.run_definition_cid
      _ => false
    }
  }
  match
    self.host.lookup_submitted_checkpoint_metadata(
      self.crypto,
      self.principal,
      self.connection,
      self.reference,
      self.request,
      now,
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
  let (context, policy) = if self.approval_scope is SavedApproval(saved) {
    match
      saved.capture.with_current_adoption_material_in_original_read((
        host,
        material,
        _,
      ) => {
        if !physical_equal(host, self.host) {
          return Err(CustodyLost)
        }
        let context = match
          saved.capture.operation_scope(
            host,
            material,
            self.installed.reviewer.principal,
            self.installed.reviewer.connection,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        @host.client_local_adopted_current_account(material, host.database)
        .map(value => (context, value.configuration_cid()))
        .map_err(local_current_material_issue)
      }) {
      Ok(value) => value
      Err(_) => return None
    }
  } else {
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
    (context, policy)
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
  if !self.original_current() || !self.installed.current() {
    return None
  }
  let terminal = match self.approval_scope {
    SavedApproval(saved) =>
      self.installed.terminal_saved_host_current(self.host, saved.capture)
    ResidentApproval(_) => self.host.check_binding()
  }
  if terminal is Err(_) {
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
  Ok({ binding: self, authentication, registration, resolution_wire, limits, })
}

///|
/// Signature authentication is only one input to the existing Resolution
/// Owner. Actual Host attestation and all common admission/commit checks still
/// apply; current Reviewer and original Client read are rechecked at admission.
/// This Local operational path consumes its adopted independent Host key
/// original. The actual attestation signing supplier is still required; no
/// public caller can choose an authority array or borrow the Reviewer key.
// Keep this private until the operational signer and original caller are joined.
#warnings("-unused_value")
fn NativeLocalAuthenticatedEffectReviewer::admit_original_resolution(
  self : NativeLocalAuthenticatedEffectReviewer,
  verified_wire : String,
  host_key : NativeLocalSigningKeyOriginal,
  now : () -> String,
) -> Result[NativeClientRunRecord, NativeLocalEffectReviewerBindingIssue] {
  let binding = self.binding
  let authority = match
    local_effect_host_attestation_authority(
      binding.host,
      host_key,
      self.registration.public_key_pem,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let current = () => {
    if binding.read_current(
        self.registration.selection,
        self.registration.key_id,
      ) !=
      Some(self.registration) {
      return false
    }
    match
      local_effect_host_attestation_authority(
        binding.host,
        host_key,
        self.registration.public_key_pem,
      ) {
      Ok(value) =>
        value.key_id == authority.key_id &&
        value.public_key_pem == authority.public_key_pem
      Err(_) => false
    }
  }
  if !current() {
    return Err(ReviewerUnavailable)
  }
  // Authenticate the actual embedded proof too. An earlier authentication of
  // an equal unsigned body cannot certify changed signature/self-CID bytes.
  let authentication = match
    @effect_resolution.authenticate_native_effect_wrapper_reviewer(
      {
        crypto: binding.crypto,
        current_site: current,
        read_current: (selection, key) => binding.read_current(selection, key),
      },
      self.registration.selection,
      verified_wire,
      self.resolution_wire,
      self.limits,
    ) {
    Err(issue) => return Err(ReviewerAuthentication(issue))
    Ok(value) => value
  }
  if authentication != self.authentication || !current() {
    return Err(ReviewerUnavailable)
  }
  binding.host.journal
  .resolve_effect_checkpoint(
    binding.request,
    binding.crypto,
    verified_wire,
    authentication,
    [
      {
        key_id: self.registration.key_id,
        reviewer_id: self.registration.reviewer_id,
      },
    ],
    [authority],
    current,
    now,
  )
  .map_err(issue => ReviewerJournal(issue))
}
