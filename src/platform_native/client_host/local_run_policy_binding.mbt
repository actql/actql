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
  profile : @host.ClientLocalRunPolicyProfile
  read_selection_cid : String
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
    let source = @source.parse_json_bytes_preserving(run, {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }).unwrap_or_else(() => raise LocalReadPolicyStop(InvalidOriginal))
    let cursor = read_policy_decoded(
      @decode.admit(source, {
        max_nodes: 8192,
        max_depth: 64,
        max_string_bytes: 8192,
        max_total_string_bytes: 65536,
      }),
    )
    let root = read_policy_decoded(
      @decode.closed_object(cursor, ["native", "version"]),
    )
    if read_policy_text(root, "version", 32) != "actql-config/0.1" {
      return Err(CustodyLost)
    }
    let native = read_policy_decoded(
      @decode.closed_object(read_policy_field(root, "native"), ["run"]),
    )
    let fields = read_policy_decoded(
      @decode.closed_object(read_policy_field(native, "run"), [
        "namespace_id", "store_name", "store_authority_cid", "store_capacity_bytes",
        "store_objects", "store_record_bytes", "result_payload_bytes", "retention_policy_wire",
        "source_free",
      ]),
    )
    let values = read_policy_decoded(
      @decode.closed_object(read_policy_field(fields, "source_free"), [
        "registry", "values", "fragment", "ordered", "result_policy_cid", "result_policy_wire",
      ]),
    )
    let policy_wire = read_policy_text(values, "result_policy_wire", 8192)
    let policy_cid = read_policy_text(values, "result_policy_cid", 71)
    if @host.admit_source_free_result_policy_body(
        policy_cid, policy_wire, 8192, 512, 8,
      )
      is Err(_) {
      return Err(CustodyLost)
    }
    Ok({
      account,
      retention_dependencies: retention,
      retention_policy: @utf8.encode(
        read_policy_text(fields, "retention_policy_wire", 8192),
      ),
      store,
      result_policy: @utf8.encode(policy_wire),
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
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let names = [profile_file, read_file, run_file, retention_file, store_file]
  let files : Array[NativeLocalSelectedFile] = []
  for name in names {
    if files.any(file => file.name == name) {
      return Err(CustodyLost)
    }
    match local_run_policy_selected(self, name) {
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
    profile,
    read_selection_cid: files[1].content_cid,
  }
  if !binding.current_for(self.journal, None, false) {
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
  let current = () => self.current_for(self.host.journal, Some(request), true)
  match
    self.host.journal.authorize_submitted_run(
      self.host.epoch,
      reference,
      request,
      self.scope,
      current(),
      now,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard preparation.preparation is Computation(prepared) else {
    return Err(UnsupportedPreparation)
  }
  if @host.prepared_client_acquisition_count(prepared) != 0 {
    return Err(UnsupportedPreparation)
  }
  match
    validate_native_client_run_binding(request, prepared, compiled, definition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let ref_record = match
    @host.admit_client_submission_reference_record(reference.wire) {
    Ok(value) => value
    Err(_) => return Err(InvalidSubmission)
  }
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
  self.host.journal.accept_original_submitted_run(
    self.host.epoch,
    reference,
    preparation.intent_cid,
    request,
    definition,
    self.scope,
    current(),
    local_run_policy_original=Some(original),
    current_fence=Some(current),
  )
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
  let current = () => self.current_for(self.host.journal, Some(request), false)
  let submission = match
    self.host.journal.lookup_submitted_intent(
      self.host.epoch,
      reference,
      self.scope,
      current(),
      now,
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
  self.host.journal.transaction(() => {
    if !current() {
      return Err(AuthorizationDenied)
    }
    let record = match self.host.journal.retained(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    guard record.local_run_policy_originals is Some(wire) &&
      @publication.publication_contract_identity(record.definition) ==
      admission.run_definition_cid else {
      return Err(CustodyLost)
    }
    let ref_record = match
      @host.admit_client_submission_reference_record(reference.wire) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
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
  })
}
