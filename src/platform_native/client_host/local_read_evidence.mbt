///|
// Metadata for the existing Native journal, separate from Run control rows.
// An absent witness is custody loss, never permission for read-time bootstrap.
fn initialize_local_read_evidence(
  database : @sqlite.Database,
  adoption : Bytes,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  for table in ["client_local_read_custody", "client_local_read_evidence"] {
    match
      scan_client_journal_value(
        database,
        table,
        "",
        bootstrap_journal_reads(bootstrap),
      ) {
      Err(@sqlite.NotFound) => ()
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
  }
  match
    bootstrap_journal_capacity_usage(
      database, "client_local_read_evidence", bootstrap,
    ) {
    Ok(value) if value.reserved_bytes == 0L && value.reserved_objects == 0L =>
      ()
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  match
    insert_bootstrap_journal_value(
      database, "client_local_read_custody", "host", adoption, bootstrap,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  insert_bootstrap_journal_value(
    database, "client_local_read_custody", "issued", b"0", bootstrap,
  )
  .map(_ => ())
  .map_err(issue => Physical(issue))
}

///|
fn local_read_evidence_packet(
  original : @host.ClientRequestIdentity,
  bodies : NativeLocalReadAdmissionOriginals,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  let request = match @host.client_request_identity_record_wire(original) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  try {
    let writer = @encode.writer(65536, 16, 4)
    @encode.begin_object(writer)
    for
      (name, body) in [
        ("authorization_context", bodies.authorization.wire),
        ("data_ceiling", bodies.ceiling.wire),
        ("egress_admission", bodies.egress.wire),
        ("request", request),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, body)
    }
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
fn local_read_evidence_object(
  bytes : Bytes,
  names : Array[String],
  limit : Int,
) -> Result[@decode.ObjectView, NativeClientRunJournalIssue] {
  let source = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limit,
      max_nodes: 256,
      max_depth: 8,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 256,
      max_depth: 8,
      max_string_bytes: limit,
      max_total_string_bytes: limit,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  @decode.closed_object(cursor, names).map_err(_ => CustodyLost)
}

///|
// Recompute exact preimages from actual retained Host, selected configuration
// and original Run. This does not claim a fresh Store observation or allow.
fn NativeLocalHostConnection::validate_read_evidence(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  row : @sqlite.NativeJournalEntry,
) -> Result[String, NativeClientRunJournalIssue] {
  guard row.revision == 0L else { return Err(CustodyLost) }
  let packet = match
    local_read_evidence_object(
      row.body,
      ["authorization_context", "data_ceiling", "egress_admission", "request"],
      65536,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard epoch_text(packet, "request") is Some(request_wire) &&
    epoch_text(packet, "authorization_context") is Some(authorization_wire) &&
    epoch_text(packet, "data_ceiling") is Some(ceiling_wire) &&
    epoch_text(packet, "egress_admission") is Some(egress_wire) else {
    return Err(CustodyLost)
  }
  let original = match
    @host.admit_client_request_identity_record_wire(request_wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let record = match self.journal.retained(original) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  let egress = match
    local_read_evidence_object(
      @utf8.encode(egress_wire),
      [
        "attempt_id", "authority_scope_cid", "authorization_context_cid", "data_ceiling_cid",
        "domain", "effective_data_policy_cid", "expires_at", "format", "material_generation_cid",
        "max_bytes", "max_uses", "principal_id", "public_index_entry_cid", "purpose",
        "read_original_cid", "result_artifact_cid", "result_definition_cid", "result_manifest_cid",
        "result_name", "run_definition_cid", "sink",
      ],
      16384,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard epoch_text(egress, "read_original_cid") is Some(read_cid) &&
    epoch_text(egress, "effective_data_policy_cid") is Some(policy_cid) &&
    record.publication_policy_originals is Some(policy_wire) else {
    return Err(CustodyLost)
  }
  // Each saved row resolves its own exact original. The closed signed append
  // is distinct from an ordinary selected file and cannot repair a missing CID.
  let (file, read_wire, upgrade) = match
    self.session.settings.files
    .iter()
    .find_first(file => file.content_cid == read_cid) {
    Some(file) => {
      let wire = @utf8.decode(file.body) catch { _ => return Err(CustodyLost) }
      (file, wire, None)
    }
    None => {
      let upgrade = match self.retained_policy_upgrade() {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      let wire = @host.client_local_run_policy_upgrade_read_wire(
        upgrade.original,
      )
      if !(local_adoption_digest(crypto, @utf8.encode(wire)) is Ok(actual) &&
        actual == read_cid) {
        return Err(CustodyLost)
      }
      (upgrade.files[0], wire, Some(upgrade))
    }
  }
  let policies = match read_run_policy_originals(policy_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !policies.any(body => {
      @publication.captured_effect_dependency_body_kind(body) == "data_policy" &&
      @publication.captured_effect_dependency_body_cid(body) == policy_cid
    }) {
    return Err(CustodyLost)
  }
  let selection = match admit_native_local_read_selection(read_wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  // Existing saved stdout preimages cannot restore a material receiver or
  // acquire its workspace merely because its configuration parses.
  if selection.sink != Stdout {
    return Err(CustodyLost)
  }
  let scope = match
    self.authority_scope_cid(selection.principal, selection.connection, crypto) {
    Ok(value) => value
    Err(_) => return Err(AuthorizationDenied)
  }
  if @host.client_request_authority_scope_cid(original) != scope ||
    !selection.enabled ||
    !selection.data_policy_cids.contains(policy_cid) {
    return Err(CustodyLost)
  }
  guard epoch_text(egress, "run_definition_cid") is Some(run_cid) &&
    run_cid == @publication.publication_contract_identity(record.definition) &&
    epoch_text(egress, "result_name") is Some(result_name) &&
    selection.result_names.contains(result_name) &&
    epoch_text(egress, "format") is Some(format) &&
    selection.formats.contains(format) &&
    epoch_text(egress, "purpose") == Some(selection.purpose) &&
    epoch_text(egress, "attempt_id") is Some(attempt_id) &&
    !attempt_id.is_empty() &&
    epoch_text(egress, "public_index_entry_cid") is Some(index_cid) &&
    epoch_text(egress, "result_manifest_cid") is Some(manifest_cid) &&
    epoch_text(egress, "result_artifact_cid") is Some(artifact_cid) &&
    epoch_text(egress, "result_definition_cid") is Some(result_cid) &&
    epoch_text(egress, "material_generation_cid") is Some(generation_cid) &&
    [index_cid, manifest_cid, artifact_cid, result_cid, generation_cid].all(
      read_policy_cid,
    ) else {
    return Err(CustodyLost)
  }
  let (expires_at, run_policy_original) = match selection.expiry {
    Absolute(expires_at) => {
      match self.require_original_legacy_policy(original) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      (expires_at, None)
    }
    AcceptedRunProfile(roles) => {
      let policy = match upgrade {
        Some(saved) => {
          if saved.scope != scope {
            return Err(AuthorizationDenied)
          }
          policy_binding_from_upgrade(self, crypto, saved)
        }
        None => {
          guard self.session.settings.files
            .iter()
            .find_first(candidate => candidate.content_cid == roles.profile_cid)
            is Some(profile_file) else {
            return Err(CustodyLost)
          }
          self.bind_run_policy_profile(
            crypto,
            selection.principal,
            selection.connection,
            profile_file.name,
            file.name,
            roles.run_file,
            roles.retention_file,
            roles.store_file,
          )
        }
      }
      let policy = match policy {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if roles.profile_cid !=
        @host.client_local_run_policy_profile_cid(policy.profile) ||
        roles.run_file != policy.run_file.name ||
        roles.retention_file != policy.retention_file.name ||
        roles.store_file != policy.store_file.name {
        return Err(CustodyLost)
      }
      let (reference, saved) = match policy.restore_read_original(record) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      (
        @host.client_local_run_policy_original_read_expires_at(saved),
        Some(
          (
            reference,
            original,
            @host.client_local_run_policy_original_body(saved),
          ),
        ),
      )
    }
  }
  let binding : NativeLocalReadPolicyBinding = {
    host: self,
    capture: None,
    crypto,
    file,
    selection,
    principal: selection.principal,
    connection: selection.connection,
    scope,
    expires_at,
    selection_cid: read_cid,
    upgrade_packet: upgrade.map(value => value.packet),
    run_policy_original,
  }
  let facts : @result_access.NativeResultReadFacts = {
    request: {
      // Namespace is already bound by the retained index entry's CID. Archive
      // reconstruction is not a new open or a Store observation.
      namespace_id: "",
      authority_scope_cid: scope,
      run_definition_cid: run_cid,
      principal_id: selection.principal,
      purpose: selection.purpose,
      result_name,
      format,
      attempt_id,
    },
    public_index_entry_cid: index_cid,
    result_manifest_cid: manifest_cid,
    result_artifact_cid: artifact_cid,
    result_definition_cid: result_cid,
    material_generation_cid: generation_cid,
    observed_at: "",
  }
  let expected = match
    binding.read_admission_preimages(original, facts, policy_cid) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if expected.authorization.wire != authorization_wire ||
    expected.ceiling.wire != ceiling_wire ||
    expected.egress.wire != egress_wire ||
    expected.egress.cid != row.key {
    return Err(CustodyLost)
  }
  match local_read_evidence_packet(original, expected) {
    Ok(body) if body == row.body => Ok(@host.client_request_scope_cid(original))
    _ => Err(CustodyLost)
  }
}

///|
fn NativeLocalHostConnection::read_evidence_custody(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
) -> Result[(Int, Int64, Map[String, (Int, Int)]), NativeClientRunJournalIssue] {
  guard self.database.scan_after("client_local_read_custody", "") is Ok(first) &&
    first.key == "host" &&
    first.revision == 0L &&
    first.body == self.adoption_body &&
    self.database.scan_after("client_local_read_custody", "host") is Ok(issued) &&
    issued.key == "issued" &&
    self.database.scan_after("client_local_read_custody", "issued")
    is Err(@sqlite.NotFound) else {
    return Err(CustodyLost)
  }
  let count_text = @utf8.decode(issued.body) catch {
    _ => return Err(CustodyLost)
  }
  if count_text.is_empty() || count_text.length() > 5 {
    return Err(CustodyLost)
  }
  let mut count = 0
  for unit in count_text {
    let digit = unit.to_int() - 48
    if digit < 0 || digit > 9 {
      return Err(CustodyLost)
    }
    count = count * 10 + digit
  }
  if count.to_string() != count_text ||
    count > self.journal.max_records * 64 ||
    issued.revision != count.to_int64() {
    return Err(CustodyLost)
  }
  let runs : Map[String, (Int, Int)] = Map(
    [],
    capacity=self.journal.max_records,
  )
  let mut cursor = ""
  let mut observed = 0
  while true {
    let row = match
      self.database.scan_after("client_local_read_evidence", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    observed += 1
    if observed > count {
      return Err(CustodyLost)
    }
    let scope = match self.validate_read_evidence(crypto, row) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let (entries, bytes) = runs.get(scope).unwrap_or((0, 0))
    if entries >= 64 || row.body.length() > 65536 - bytes {
      return Err(CustodyLost)
    }
    runs[scope] = (entries + 1, bytes + row.body.length())
    if runs.length() > self.journal.max_records {
      return Err(CustodyLost)
    }
    cursor = row.key
  }
  if observed != count {
    return Err(CustodyLost)
  }
  guard self.database.capacity_usage("client_local_read_evidence") is Ok(usage) &&
    usage.reserved_objects == runs.length().to_int64() &&
    usage.reserved_bytes == runs.length().to_int64() * 65536L else {
    return Err(CustodyLost)
  }
  Ok((count, issued.revision, runs))
}

///|
/// Current read admission retains exact originals in the original journal's
/// transaction before returning references to the existing grant issuer.
/// No Run control row/revision, grant, payload or attempt is created here.
pub fn NativeLocalReadPolicyBinding::admit_read(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  facts : @result_access.NativeResultReadFacts,
) -> Result[
  @result_access.NativeResultReadAdmission,
  NativeLocalReadBindingIssue,
] {
  let policy = match self.resolve_policy_original(original, store, facts) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.retain_read_admission(
    original,
    facts,
    @publication.captured_effect_dependency_body_cid(policy),
  )
}

///|
// Internal custody step; the public caller above resolves actual Store facts.
fn NativeLocalReadPolicyBinding::retain_read_admission(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  actual_policy_cid : String,
) -> Result[
  @result_access.NativeResultReadAdmission,
  NativeLocalReadBindingIssue,
] {
  let mut authority_refusal : NativeLocalReadBindingIssue? = None
  let stored = self.host.journal.transaction(() => {
    match self.require_request(original, facts) {
      Ok(_) => ()
      Err(issue) => {
        authority_refusal = Some(issue)
        return Err(AuthorizationDenied)
      }
    }
    if !self.selection.data_policy_cids.contains(actual_policy_cid) {
      authority_refusal = Some(PolicyNotSelected)
      return Err(AuthorizationDenied)
    }
    let record = match self.host.journal.retained(original) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    if @publication.publication_contract_identity(record.definition) !=
      facts.request.run_definition_cid {
      return Err(ForeignRun)
    }
    guard record.publication_policy_originals is Some(policy_wire) else {
      return Err(PublicationPolicy(@checked.MissingDependency))
    }
    let policies = match read_run_policy_originals(policy_wire) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !policies.any(body => {
        @publication.captured_effect_dependency_body_kind(body) == "data_policy" &&
        @publication.captured_effect_dependency_body_cid(body) ==
        actual_policy_cid
      }) {
      return Err(PublicationPolicy(@checked.MissingDependency))
    }
    let (count, revision, runs) = match
      self.host.read_evidence_custody(self.crypto) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let scope = @host.client_request_scope_cid(original)
    let (entries, used_bytes) = runs.get(scope).unwrap_or((0, 0))
    // The same durable per-Run reservation covers bounded originals, before
    // copying/encoding. Existing reservation loss cannot be silently repaired.
    match
      self.host.database.reserve_capacity_in_transaction(
        "client_local_read_evidence",
        scope,
        65536L,
        1L,
        self.host.journal.max_records.to_int64() * 65536L,
        self.host.journal.max_records.to_int64(),
      ) {
      Ok(fresh) if fresh == (entries == 0) => ()
      Ok(_) => return Err(CustodyLost)
      Err(@sqlite.CapacityExceeded) => return Err(CapacityExceeded)
      Err(issue) => return Err(Physical(issue))
    }
    let bodies = match
      self.read_admission_originals(original, facts, actual_policy_cid) {
      Ok(value) => value
      Err(issue) => {
        authority_refusal = Some(issue)
        return Err(AuthorizationDenied)
      }
    }
    let packet = match local_read_evidence_packet(original, bodies) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match
      self.host.database.read("client_local_read_evidence", bodies.egress.cid) {
      Ok(row) if row.revision == 0L && row.body == packet => ()
      Ok(_) => return Err(CustodyLost)
      Err(@sqlite.NotFound) => {
        if entries >= 64 || packet.length() > 65536 - used_bytes {
          return Err(CapacityExceeded)
        }
        match
          self.host.database.insert(
            "client_local_read_evidence",
            bodies.egress.cid,
            packet,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Physical(issue))
        }
        match
          self.host.database.compare_exchange(
            "client_local_read_custody",
            "issued",
            revision,
            @utf8.encode((count + 1).to_string()),
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Physical(issue))
        }
      }
      Err(issue) => return Err(Physical(issue))
    }
    match self.require_request(original, facts) {
      Ok(_) => {
        let admission : @result_access.NativeResultReadAdmission = {
          authorization_context_cid: bodies.authorization.cid,
          data_ceiling_cid: bodies.ceiling.cid,
          egress_admission_cid: bodies.egress.cid,
          expires_at: self.expires_at,
          max_bytes: self.selection.max_bytes,
          max_uses: self.selection.max_uses,
        }
        Ok(admission)
      }
      Err(issue) => {
        authority_refusal = Some(issue)
        Err(AuthorizationDenied)
      }
    }
  })
  match stored {
    Ok(value) => Ok(value)
    Err(TransactionUnknown) => Err(Journal(TransactionUnknown))
    Err(issue) => Err(authority_refusal.unwrap_or(Journal(issue)))
  }
}
