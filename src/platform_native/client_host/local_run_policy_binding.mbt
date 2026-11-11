///|
// Retained selected originals plus the existing physical Host, not a public
// profile CID or an allow callback. This binding issues no Policy or grant.
struct NativeLocalRunPolicyBinding {
  host : NativeLocalHostConnection
  crypto : @crypto.Library
  principal : String
  connection : String
  scope : String
  files : Array[NativeLocalSelectedFile]
  read_file : NativeLocalSelectedFile
  run_file : NativeLocalSelectedFile
  retention_file : NativeLocalSelectedFile
  store_file : NativeLocalSelectedFile
  origin : NativeLocalRunPolicyOrigin
  profile : @host.ClientLocalRunPolicyProfile
  read_selection_cid : String
}

///|
priv enum NativeLocalRunPolicyOrigin {
  Selected
  Upgraded(Bytes, String)
}

///|
/// This is a preparation decision, not durable acceptance or a dispatch permit.
/// Only Pending requires a new checked compilation and first accept transaction.
pub(all) enum NativeLocalRunPolicyPreparation {
  Accepted(@host.ClientLocalRunPolicyOriginal)
  Pending(@publication.PublicationContract, String)
}

///|
fn local_run_policy_selected(
  host : NativeLocalHostConnection,
  name : String,
) -> Result[NativeLocalSelectedFile, NativeClientRunJournalIssue] {
  if host.selected_configuration(name) is Err(_) {
    return Err(CustodyLost)
  }
  match
    host.session.settings.files.iter().find_first(file => file.name == name) {
    Some(file) => Ok(file)
    None => Err(CustodyLost)
  }
}

///|
// The existing bounded full-parse/metadata projection preserves the selected
// Run original. No filename search, new parser or replacement policy is used.
fn local_run_policy_run_fields(
  run : Bytes,
) -> @decode.ObjectView raise LocalReadPolicyStop {
  let cursor = @host.client_local_run_policy_metadata_cursor(run).unwrap_or_else(() => {
      raise LocalReadPolicyStop(InvalidOriginal)
    },
  )
  let root = read_policy_decoded(
    @decode.closed_object(cursor, ["native", "version"]),
  )
  if read_policy_text(root, "version", 32) != "actql-config/0.1" {
    raise LocalReadPolicyStop(InvalidOriginal)
  }
  let native = read_policy_decoded(
    @decode.closed_object(read_policy_field(root, "native"), ["run"]),
  )
  read_policy_decoded(
    @decode.closed_object(read_policy_field(native, "run"), [
      "namespace_id", "store_name", "store_authority_cid", "store_capacity_bytes",
      "store_objects", "store_record_bytes", "result_payload_bytes", "retention_policy_wire",
      "source_free",
    ]),
  )
}

///|
fn local_run_policy_source_free_original(
  fields : @decode.ObjectView,
) -> @publication.CapturedEffectDependencyBody raise LocalReadPolicyStop {
  let values = read_policy_decoded(
    @decode.closed_object(read_policy_field(fields, "source_free"), [
      "registry", "values", "fragment", "ordered", "result_policy_cid", "result_policy_wire",
    ]),
  )
  let policy_wire = read_policy_text(values, "result_policy_wire", 8192)
  let policy_cid = read_policy_text(values, "result_policy_cid", 71)
  @host.admit_source_free_result_policy_body(
    policy_cid, policy_wire, 8192, 512, 8,
  ).unwrap_or_else(() => raise LocalReadPolicyStop(InvalidOriginal))
}

///|
// Extract only actual selected originals. The old absolute retention body is
// admitted as an original dependency, never interpreted as a rolling lifetime.
fn local_run_policy_common_originals(
  account : Bytes,
  run : Bytes,
  retention : Bytes,
  store : Bytes,
) -> Result[
  @host.ClientLocalProductCommonOriginals,
  NativeClientRunJournalIssue,
] {
  try {
    let fields = local_run_policy_run_fields(run)
    let policy = local_run_policy_source_free_original(fields)
    Ok({
      account,
      retention_dependencies: retention,
      retention_policy: @utf8.encode(
        read_policy_text(fields, "retention_policy_wire", 8192),
      ),
      store,
      result_policy: @utf8.encode(
        @publication.captured_effect_dependency_body_json(policy),
      ),
    })
  } catch {
    LocalReadPolicyStop(_) => Err(CustodyLost)
  }
}

///|
/// A distinct profile must be explicitly present in the adopted selection.
/// Legacy installations without it remain absolute; no discovery or repair is
/// performed. All five configuration originals retain their file generations.
pub fn NativeLocalHostConnection::bind_run_policy_profile(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  profile_file : String,
  read_file : String,
  run_file : String,
  retention_file : String,
  store_file : String,
) -> Result[NativeLocalRunPolicyBinding, NativeClientRunJournalIssue] {
  self.bind_run_policy_profile_with_capture(
    crypto, principal, connection, profile_file, read_file, run_file, retention_file,
    store_file,
  )
}

///|
fn NativeLocalHostConnection::bind_run_policy_profile_with_capture(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  profile_file : String,
  read_file : String,
  run_file : String,
  retention_file : String,
  store_file : String,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[NativeLocalRunPolicyBinding, NativeClientRunJournalIssue] {
  let selected_scope = match capture {
    Some(original) => {
      guard original.opening is JournalAcquired(host) &&
        physical_equal(host, self) else {
        return Err(CustodyLost)
      }
      original.authority_scope_cid_in_original_read(principal, connection)
    }
    None => self.authority_scope_cid(principal, connection, crypto)
  }
  let scope = match selected_scope {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let names = [profile_file, read_file, run_file, retention_file, store_file]
  let files : Array[NativeLocalSelectedFile] = []
  for name in names {
    if files.any(file => file.name == name) {
      return Err(CustodyLost)
    }
    let selected : Result[NativeLocalSelectedFile, NativeClientRunJournalIssue] = match
      capture {
      Some(original) => {
        match original.selected_configuration_in_original_read(name) {
          Err(_) => return Err(CustodyLost)
          Ok(_) => ()
        }
        match
          self.session.settings.files
          .iter()
          .find_first(file => file.name == name) {
          Some(file) => Ok(file)
          None => Err(CustodyLost)
        }
      }
      None => local_run_policy_selected(self, name)
    }
    match selected {
      Ok(file) => files.push(file)
      Err(issue) => return Err(issue)
    }
  }
  let originals = match
    local_run_policy_common_originals(
      self.session.source_body,
      files[2].body,
      files[3].body,
      files[4].body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let text = @utf8.decode(files[0].body) catch { _ => return Err(Encoding) }
  let profile = match
    @host.admit_client_local_run_policy_profile(text, originals) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  // The read original's identity is retained independently of Run submit.
  // Its disclosure selectors and expiry still require the read Policy Owner.
  let binding : NativeLocalRunPolicyBinding = {
    host: self,
    crypto,
    principal,
    connection,
    scope,
    files,
    read_file: files[1],
    run_file: files[2],
    retention_file: files[3],
    store_file: files[4],
    origin: Selected,
    profile,
    read_selection_cid: files[1].content_cid,
  }
  let current = match capture {
    Some(original) => binding.current_in_original_read(original, None, false)
    None => binding.current_for(self.journal, None, false)
  }
  if !current {
    return Err(AuthorizationDenied)
  }
  Ok(binding)
}

///|
fn NativeLocalRunPolicyBinding::current_for(
  self : NativeLocalRunPolicyBinding,
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity?,
  new_submission : Bool,
) -> Bool {
  if !physical_equal(self.host.journal, journal) ||
    !(self.host.authority_scope_cid(
      self.principal,
      self.connection,
      self.crypto,
    )
    is Ok(current) &&
    current == self.scope) ||
    (
      request is Some(original) &&
      @host.client_request_authority_scope_cid(original) != self.scope
    ) {
    return false
  }
  for file in self.files {
    if !(self.host.selected_configuration(file.name) is Ok(body) &&
      body == file.body) {
      return false
    }
  }
  if self.origin is Upgraded(packet, _) {
    guard self.host.database.read(
        "client_local_installation_originals", local_policy_upgrade_key,
      )
      is Ok(row) &&
      row.revision == 0L &&
      row.body == packet else {
      return false
    }
    if self.host.with_installation_custody(() => Ok(())) is Err(_) {
      return false
    }
  }
  let operations = if new_submission {
    ["submit", "publish", "read"]
  } else {
    ["read"]
  }
  for operation in operations {
    if !(self.host.authorize({
        principal: self.principal,
        connection: self.connection,
        resource: "run",
        operation,
      })
      is Ok(@authorization.Allow(_))) {
      return false
    }
  }
  true
}

///|
// Read-only archive validation inside the existing read-evidence custody walk.
// It does not begin a nested transaction, sample time or reopen a payload.
fn NativeLocalRunPolicyBinding::restore_read_original(
  self : NativeLocalRunPolicyBinding,
  record : NativeClientRunRecord,
  reads? : NativeClientJournalReadAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[
  (NativeClientSubmissionReference, @host.ClientLocalRunPolicyOriginal),
  NativeClientRunJournalIssue,
] {
  let current = () => {
    match capture {
      None => self.current_for(self.host.journal, Some(record.request), false)
      Some(original) =>
        self.current_in_original_read(original, Some(record.request), false)
    }
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  guard record.local_run_policy_originals is Some(wire) else {
    return Err(CustodyLost)
  }
  let fields = match
    @host.client_local_original_record_fields(@utf8.encode(wire), [
      "host_adoption_cid", "issued_at", "profile_wire", "read_selection_cid", "request_wire",
      "retention_policy_wire", "run_definition_cid", "submission_reference_wire",
      "version",
    ]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let reference = match admit_native_client_submission_reference(fields[7]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  match
    self.host.journal.verify_submission_locked(
      self.host.epoch,
      reference,
      self.scope,
      current(),
      reads~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard self.host.journal.retained_submission(reference, reads~)
    is Ok(Some(submission)) &&
    submission.run_admission is Some(admission) &&
    @host.client_request_identity_relation(admission.request, record.request) ==
    @host.SameRequest &&
    admission.run_definition_cid ==
    @publication.publication_contract_identity(record.definition) else {
    return Err(CustodyLost)
  }
  let ref_record = reference.original
  let original = match
    @host.admit_client_local_run_policy_original(
      @utf8.encode(wire),
      self.profile,
      ref_record,
      record.request,
      record.definition,
      self.host.adoption_cid(),
      self.read_selection_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  Ok((reference, original))
}

///|
/// Look up the original operation before considering any new Policy issuance.
/// An accepted request reuses its saved Policy/issuance time even when the
/// supplied candidate observation time is invalid or later. Unknown/missing
/// custody never becomes Pending. The CLI supplies its actual clock only for
/// a genuinely new first acceptance candidate; the transaction still decides
/// the winning Run and prevents concurrent candidates from replacing it.
pub fn NativeLocalRunPolicyBinding::prepare_submission_policy(
  self : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  observed_at : String,
  now : Double,
) -> Result[NativeLocalRunPolicyPreparation, NativeClientRunJournalIssue] {
  self.prepare_submission_policy_with_operations(
    reference,
    preparation,
    request,
    observed_at,
    now,
    () => self.current_for(self.host.journal, Some(request), false),
    () => self.current_for(self.host.journal, Some(request), true),
  )
}

///|
// Pure checked identity for pending lifetime selection, not Run admission.
fn native_local_run_policy_preparation_identity(
  preparation : NativeClientSubmittedPreparation,
) -> Result[@host.ClientProgramIdentity, NativeClientRunJournalIssue] {
  // Pending lifetime selection binds checked identity only. Execution shape,
  // original managed Plan and current authority are checked at acceptance.
  Ok(
    match preparation.preparation {
      Computation(prepared) => @host.prepared_client_identity(prepared)
      EffectComputation(prepared) =>
        @host.prepared_client_effect_identity(prepared)
    },
  )
}

///|
// Preserve legacy Values acceptance. A Source caller must instead retain the
// genuine live preparation-owned Run, its SAME Request and original compiler
// artifact. These pure projections grant no Host/Read/physical start authority.
fn native_local_run_policy_compilation_original(
  prepared : @host.PreparedClientProgram,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  managed : @local.ClientInstalledManagedRun?,
) -> Bool {
  if @host.prepared_client_acquisition_count(prepared) == 0 {
    return true
  }
  guard managed is Some(run) &&
    @local.installed_managed_preparation_admission_original(
      run, prepared, request,
    )
    is Some(_) &&
    @local.installed_managed_capture_publication_geometry_original(
      run, prepared, request,
    )
    is Some(_) &&
    @local.installed_managed_run_compilation_original(run, prepared)
    is Some(compilation) else {
    return false
  }
  @host.client_compiled_run_matches_pure_compilation(
    compiled, prepared, compilation,
  )
}

///|
fn NativeLocalRunPolicyBinding::prepare_submission_policy_with_operations(
  self : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  observed_at : String,
  now : Double,
  current_read : () -> Bool,
  current_submission : () -> Bool,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeLocalRunPolicyPreparation, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  match
    self.host.journal.lookup_submitted_intent_with_operations(
      self.host.epoch,
      reference,
      self.scope,
      current_read(),
      now,
      operations~,
    ) {
    Ok(Submitted(_)) => ()
    Ok(UnresolvedSubmissionHistory) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  let identity = match
    native_local_run_policy_preparation_identity(preparation) {
    Ok(identity) => identity
    Err(issue) => return Err(issue)
  }
  if identity.program_definition_cid !=
    @host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @host.client_request_parameters_cid(request) {
    return Err(ChangedIntent)
  }
  self.host.journal.transaction_with_reads(
    () => {
      if !current_read() {
        return Err(AuthorizationDenied)
      }
      let original = match
        self.host.journal.retained_submission(reference, reads~) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if @host.client_submitted_intent_cid(original.intent) !=
        preparation.intent_cid {
        return Err(ChangedIntent)
      }
      if original.run_admission is Some(admission) {
        if @host.client_request_identity_relation(admission.request, request) !=
          @host.SameRequest {
          return Err(ChangedIntent)
        }
        let run = match self.host.journal.retained(request, reads~) {
          Ok(Some(value)) => value
          Ok(None) => return Err(CustodyLost)
          Err(issue) => return Err(issue)
        }
        guard run.local_run_policy_originals is Some(wire) &&
          admission.run_definition_cid ==
          @publication.publication_contract_identity(run.definition) else {
          return Err(CustodyLost)
        }
        let ref_record = reference.original
        let saved = match
          @host.admit_client_local_run_policy_original(
            @utf8.encode(wire),
            self.profile,
            ref_record,
            request,
            run.definition,
            self.host.adoption_cid(),
            self.read_selection_cid,
          ) {
          Ok(value) => value
          Err(_) => return Err(CustodyLost)
        }
        if !current_read() {
          return Err(AuthorizationDenied)
        }
        return Ok(Accepted(saved))
      }
      // A pre-existing Run with missing admission is lost custody, not a new
      // first acceptance and not permission to issue another lifetime.
      match self.host.journal.retained(request, reads~) {
        Ok(None) => ()
        Ok(Some(_)) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if !current_submission() {
        return Err(AuthorizationDenied)
      }
      let policy = match
        @host.issue_client_local_run_retention_policy(self.profile, observed_at) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      if !current_submission() {
        return Err(AuthorizationDenied)
      }
      Ok(Pending(policy, observed_at))
    },
    reads~,
  )
}

///|
/// Accept exact checked computation and already-issued original in the existing
/// transaction. This does not issue a lifetime, start work or grant Result read.
pub fn NativeLocalRunPolicyBinding::accept_submitted_run(
  self : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  original : @host.ClientLocalRunPolicyOriginal,
  now : Double,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  self.accept_submitted_run_with_operations(
    reference,
    preparation,
    request,
    compiled,
    definition,
    original,
    now,
    () => self.current_for(self.host.journal, Some(request), true),
  )
}

///|
fn NativeLocalRunPolicyBinding::accept_submitted_run_with_operations(
  self : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  original : @host.ClientLocalRunPolicyOriginal,
  now : Double,
  current : () -> Bool,
  operations? : NativeClientJournalOperationAccess? = None,
  managed? : @local.ClientInstalledManagedRun? = None,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  match
    self.host.journal.authorize_submitted_run(
      self.host.epoch,
      reference,
      request,
      self.scope,
      current(),
      now,
      operations~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard preparation.preparation is Computation(prepared) else {
    return Err(UnsupportedPreparation)
  }
  if !native_local_run_policy_compilation_original(
      prepared, request, compiled, managed,
    ) {
    return Err(UnsupportedPreparation)
  }
  match
    self.host.journal.validate_prepared_run_binding(
      request, prepared, compiled, definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let ref_record = reference.original
  if @host.admit_client_local_run_policy_original(
      @host.client_local_run_policy_original_body(original),
      self.profile,
      ref_record,
      request,
      definition,
      self.host.adoption_cid(),
      self.read_selection_cid,
    )
    is Err(_) {
    return Err(CustodyLost)
  }
  let observation = match
    capture_native_run_observation_originals(compiled, definition) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let plan = match
    capture_native_run_plan_original(prepared, compiled, definition) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.host.journal.accept_original_submitted_run(
    self.host.epoch,
    reference,
    preparation.intent_cid,
    request,
    definition,
    self.scope,
    current(),
    local_run_policy_original=Some(original),
    run_observation_originals=Some(observation),
    run_plan_original=Some(plan),
    current_fence=Some(current),
    operations~,
  )
}

///|
/// Bind the CLI's first candidate through the actual adopted profile. The
/// checked preparation, current fences and original accept CAS remain with
/// accept_submitted_run; neither metadata nor this call authorizes dispatch.
pub fn NativeLocalRunPolicyBinding::accept_issued_submitted_run_policy(
  self : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  issued_at : String,
  now : Double,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  let original = match
    self.issued_policy_original(
      reference, request, definition, retention, issued_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.accept_submitted_run(
    reference, preparation, request, compiled, definition, original, now,
  )
}

///|
fn NativeLocalRunPolicyBinding::issued_policy_original(
  self : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  issued_at : String,
) -> Result[@host.ClientLocalRunPolicyOriginal, NativeClientRunJournalIssue] {
  let ref_record = reference.original
  match
    @host.bind_client_local_run_policy_original(
      self.profile,
      ref_record,
      request,
      definition,
      retention,
      issued_at,
      self.host.adoption_cid(),
      self.read_selection_cid,
    ) {
    Ok(value) => Ok(value)
    Err(_) => Err(CustodyLost)
  }
}

///|
/// Read only the original accepted packet. No clock, Policy issuer, compile,
/// Store open, grant, Source or dispatch is reachable from this operation.
pub fn NativeLocalRunPolicyBinding::lookup_submitted_run_policy(
  self : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
) -> Result[@host.ClientLocalRunPolicyOriginal, NativeClientRunJournalIssue] {
  self.lookup_submitted_run_policy_with_operations(reference, request, now, () => {
    self.current_for(self.host.journal, Some(request), false)
  })
}

///|
fn NativeLocalRunPolicyBinding::lookup_submitted_run_policy_with_operations(
  self : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  now : Double,
  current : () -> Bool,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[@host.ClientLocalRunPolicyOriginal, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  let submission = match
    self.host.journal.lookup_submitted_intent_with_operations(
      self.host.epoch,
      reference,
      self.scope,
      current(),
      now,
      operations~,
    ) {
    Ok(Submitted(value)) => value
    Ok(UnresolvedSubmissionHistory) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  guard submission.run_admission is Some(admission) &&
    @host.client_request_identity_relation(admission.request, request) ==
    @host.SameRequest else {
    return Err(CustodyLost)
  }
  let observe : () -> Result[
    @host.ClientLocalRunPolicyOriginal,
    NativeClientRunJournalIssue,
  ] = () => {
    if !current() {
      return Err(AuthorizationDenied)
    }
    let record = match self.host.journal.retained(request, reads~) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    guard record.local_run_policy_originals is Some(wire) &&
      @publication.publication_contract_identity(record.definition) ==
      admission.run_definition_cid else {
      return Err(CustodyLost)
    }
    let ref_record = reference.original
    let original = match
      @host.admit_client_local_run_policy_original(
        @utf8.encode(wire),
        self.profile,
        ref_record,
        request,
        record.definition,
        self.host.adoption_cid(),
        self.read_selection_cid,
      ) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    if !current() {
      return Err(AuthorizationDenied)
    }
    Ok(original)
  }
  if self.host.journal.operation_active && operations is Some(_) {
    // This closed command already owns the current Read and selected originals.
    // Restoring immutable Policy metadata neither mutates SQL nor opens a new
    // authorization frame. Standalone callers keep their original transaction.
    match self.host.journal.check_transaction_context(reads~) {
      Ok(_) => ()
      Err(issue) => {
        self.host.journal.invalidate_operation_record()
        return Err(issue)
      }
    }
    let result = observe()
    if result is Err(_) {
      self.host.journal.invalidate_operation_record()
    }
    result
  } else {
    self.host.journal.transaction_with_reads(observe, reads~)
  }
}

///|
/// Mode correspondence only, under current read authority. A Boolean here is
/// never a read grant; both delivery paths still use the original read Owner.
pub fn NativeLocalRunPolicyBinding::original_run_requires_finite_policy(
  self : NativeLocalRunPolicyBinding,
  request : @host.ClientRequestIdentity,
) -> Result[Bool, NativeClientRunJournalIssue] {
  if !self.current_for(self.host.journal, Some(request), false) {
    return Err(AuthorizationDenied)
  }
  let run = match self.host.journal.retained(request) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  let finite = match run.local_run_policy_originals {
    Some(_) => true
    None => {
      if self.origin is Selected {
        return Err(CustodyLost)
      }
      match self.host.require_original_legacy_policy(request) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      false
    }
  }
  if !self.current_for(self.host.journal, Some(request), false) {
    return Err(AuthorizationDenied)
  }
  Ok(finite)
}

///|
/// Select the finite roles declared by this exact read original. The caller's
/// actual configured Run must agree; no other role/profile is searched for.
pub fn NativeLocalHostConnection::bind_run_policy_profile_for_read(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  profile_file : String,
  read_file : String,
  run_file : String,
) -> Result[NativeLocalRunPolicyBinding, NativeClientRunJournalIssue] {
  let file = match local_run_policy_selected(self, read_file) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let wire = @utf8.decode(file.body) catch { _ => return Err(CustodyLost) }
  let selection = match admit_native_local_read_selection(wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard selection.expiry is AcceptedRunProfile(roles) &&
    roles.run_file == run_file else {
    return Err(ChangedIntent)
  }
  let selected_profile = match local_run_policy_selected(self, profile_file) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if roles.profile_cid != selected_profile.content_cid ||
    selection.principal != principal ||
    selection.connection != connection {
    return Err(ChangedIntent)
  }
  self.bind_run_policy_profile(
    crypto,
    principal,
    connection,
    profile_file,
    read_file,
    roles.run_file,
    roles.retention_file,
    roles.store_file,
  )
}
