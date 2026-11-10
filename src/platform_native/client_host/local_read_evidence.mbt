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
  request_wire? : String? = None,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  let request = match request_wire {
    Some(wire) => wire
    None =>
      match @host.client_request_identity_record_wire(original) {
        Ok(value) => value
        Err(_) => return Err(Encoding)
      }
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
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[String, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  guard row.revision == 0L else { return Err(CustodyLost) }
  // Count actual archived-packet admission attempts, not cache hits/getters.
  native_timing_count(42)
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
  let record = match self.journal.retained(original, reads~) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  let egress = match local_read_egress_fields(egress_wire) {
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
      if capture is Some(_) {
        return Err(AuthorizationDenied)
      }
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
  let policies = match self.journal.publication_originals(policy_wire) {
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
  // Archive integrity only: preserve the saved material identities without
  // reconstructing a receiver or obtaining another read/holding permission.
  let material_original = if selection.sink == Material {
    guard epoch_text(egress, "sink") == Some("material") &&
      epoch_text(egress, "material_receiver_cid") is Some(receiver_cid) &&
      !receiver_cid.is_empty() &&
      epoch_text(egress, "result_schema_cid") is Some(result_schema_cid) &&
      !result_schema_cid.is_empty() &&
      epoch_text(egress, "ordering_evidence_cid") is Some(ordering_evidence_cid) &&
      !ordering_evidence_cid.is_empty() else {
      return Err(CustodyLost)
    }
    Some({ receiver_cid, result_schema_cid, ordering_evidence_cid, })
  } else {
    if epoch_text(egress, "sink") !=
      Some(if selection.sink == File { "file" } else { "stdout" }) ||
      @decode.lookup(egress, "material_receiver_cid") is Some(_) ||
      @decode.lookup(egress, "result_schema_cid") is Some(_) ||
      @decode.lookup(egress, "ordering_evidence_cid") is Some(_) {
      return Err(CustodyLost)
    }
    None
  }
  let file_original = if selection.sink == File {
    match read_local_file_destination_original(egress) {
      Ok(value) => Some(value)
      Err(issue) => return Err(issue)
    }
  } else {
    for
      name in [
        "destination_path", "destination_name", "destination_staging_name", "destination_parent_device",
        "destination_parent_inode", "destination_writer_device", "destination_writer_inode",
      ] {
      if @decode.lookup(egress, name) is Some(_) {
        return Err(CustodyLost)
      }
    }
    None
  }
  let selected_scope = match capture {
    None =>
      self.authority_scope_cid(
        selection.principal,
        selection.connection,
        crypto,
      )
    Some(original) =>
      original.authority_scope_cid_in_original_read(
        selection.principal,
        selection.connection,
      )
  }
  let scope = match selected_scope {
    Ok(value) => value
    Err(_) => return Err(AuthorizationDenied)
  }
  if @host.client_request_authority_scope_cid(original) != scope ||
    !selection.enabled {
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
      if capture is Some(_) {
        return Err(AuthorizationDenied)
      }
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
          let run_read_file = if selection.sink == Material ||
            selection.sink == File {
            // Duration/custody comes from the exact original Run admission;
            // the independent Material file never replaces its read CID.
            guard record.local_run_policy_originals is Some(wire) &&
              @host.client_local_original_record_fields(@utf8.encode(wire), [
                "host_adoption_cid", "issued_at", "profile_wire", "read_selection_cid",
                "request_wire", "retention_policy_wire", "run_definition_cid", "submission_reference_wire",
                "version",
              ])
              is Ok(fields) &&
              self.session.settings.files
              .iter()
              .find_first(candidate => candidate.content_cid == fields[3])
              is Some(original_read) else {
              return Err(CustodyLost)
            }
            original_read.name
          } else {
            file.name
          }
          self.bind_run_policy_profile_with_capture(
            crypto,
            selection.principal,
            selection.connection,
            profile_file.name,
            run_read_file,
            roles.run_file,
            roles.retention_file,
            roles.store_file,
            capture~,
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
      let (reference, saved) = match
        policy.restore_read_original(record, reads~, capture~) {
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
    capture,
    crypto,
    file,
    selection,
    principal: selection.principal,
    connection: selection.connection,
    scope,
    expires_at,
    selection_cid: read_cid,
    material_receiver: None,
    material_original,
    file_destination: None,
    file_original,
    file_store: None,
    file_preparation: None,
    upgrade_packet: upgrade.map(value => value.packet),
    run_policy_original,
    result_policy_original: None,
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
  // This authenticated saved row was issued only after the original committed
  // Result root joined the first accepted Policy packet. Reconstruct its exact
  // immutable correspondence, never a Store observation or current read grant.
  if selection.policy is AcceptedRunPolicy {
    binding.result_policy_original = Some((original, facts, policy_cid))
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
fn local_read_evidence_issuance_count(
  body : Bytes,
  revision : Int64,
  max_records : Int,
) -> Result[Int, NativeClientRunJournalIssue] {
  local_journal_related_issuance_count(body, revision, max_records)
}

///|
fn NativeLocalHostConnection::read_evidence_custody(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
  max_inspect_rows? : Int64? = None,
) -> Result[(Int, Int64, Map[String, (Int, Int)]), NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  guard scan_client_journal_value(
      self.database,
      "client_local_read_custody",
      "",
      reads,
    )
    is Ok(first) &&
    first.key == "host" &&
    first.revision == 0L &&
    first.body == self.adoption_body &&
    scan_client_journal_value(
      self.database,
      "client_local_read_custody",
      "host",
      reads,
    )
    is Ok(issued) &&
    issued.key == "issued" &&
    scan_client_journal_value(
      self.database,
      "client_local_read_custody",
      "issued",
      reads,
    )
    is Err(@sqlite.NotFound) else {
    return Err(CustodyLost)
  }
  let count = match
    local_read_evidence_issuance_count(
      issued.body,
      issued.revision,
      self.journal.max_records,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if max_inspect_rows is Some(limit) && (limit < 0L || count.to_int64() > limit) {
    return Err(CapacityExceeded)
  }
  let runs : Map[String, (Int, Int)] = Map([])
  let mut cursor = ""
  let mut observed = 0
  // This is a complete evidence-namespace inventory attempt, even if empty.
  native_timing_count(41)
  while true {
    let row = match
      scan_client_journal_value(
        self.database,
        "client_local_read_evidence",
        cursor,
        reads,
      ) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    if observed >= count {
      return Err(CustodyLost)
    }
    observed += 1
    let scope = match
      self.validate_read_evidence(crypto, row, operations~, capture~) {
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
  guard client_journal_capacity_usage(
      self.database,
      "client_local_read_evidence",
      operations,
    )
    is Ok(usage) &&
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
  match self.capture {
    None =>
      self.retain_read_admission_with_operations(
        original, facts, actual_policy_cid,
      )
    Some(capture) =>
      read_binding_in_original_read(capture, (host, operations) => {
        if !physical_equal(host, self.host) {
          return Err(SelectionMismatch)
        }
        self.retain_read_admission_with_operations(
          original,
          facts,
          actual_policy_cid,
          operations=Some(operations),
        )
      })
  }
}

///|
fn NativeLocalReadPolicyBinding::retain_read_admission_with_operations(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  actual_policy_cid : String,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[
  @result_access.NativeResultReadAdmission,
  NativeLocalReadBindingIssue,
] {
  let reads = operations.map(value => value.reads)
  let mut authority_refusal : NativeLocalReadBindingIssue? = None
  let committed_bodies : Ref[NativeLocalReadAdmissionOriginals?] = Ref(None)
  let stored = self.host.journal.transaction_with_reads(
    () => {
      match self.require_request(original, facts) {
        Ok(_) => ()
        Err(issue) => {
          authority_refusal = Some(issue)
          return Err(AuthorizationDenied)
        }
      }
      match self.selected_policy_cids(original, facts, actual_policy_cid) {
        Err(issue) => {
          authority_refusal = Some(issue)
          return Err(AuthorizationDenied)
        }
        Ok(_) => ()
      }
      let record = match self.host.journal.retained(original, reads~) {
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
      let policies = match
        self.host.journal.publication_originals(policy_wire) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !policies.any(body => {
          @publication.captured_effect_dependency_body_kind(body) ==
          "data_policy" &&
          @publication.captured_effect_dependency_body_cid(body) ==
          actual_policy_cid
        }) {
        return Err(PublicationPolicy(@checked.MissingDependency))
      }
      match self.host.journal.require_read_evidence_schema(reads~) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let (count, revision) = match self.host.read_evidence_issuance(reads~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let request_wire = match
        @host.client_request_identity_record_wire(original) {
        Ok(value) => value
        Err(_) => return Err(Encoding)
      }
      let (entry_count, byte_count) = match
        read_client_journal_evidence_usage(
          self.host.database,
          request_wire,
          64L,
          65536L,
          operations,
        ) {
        Ok(value) => value
        Err(@sqlite.CapacityExceeded) => return Err(CapacityExceeded)
        Err(issue) => return Err(Physical(issue))
      }
      if entry_count < 0L ||
        entry_count > 64L ||
        entry_count > count.to_int64() ||
        byte_count < 0L ||
        byte_count > 65536L {
        return Err(CustodyLost)
      }
      let entries = entry_count.to_int()
      let used_bytes = byte_count.to_int()
      let scope = @host.client_request_scope_cid(original)
      // The same durable per-Run reservation covers bounded originals, before
      // copying/encoding. Existing reservation loss cannot be silently repaired.
      match
        reserve_client_journal_capacity(
          self.host.database,
          "client_local_read_evidence",
          scope,
          65536L,
          1L,
          self.host.journal.max_records.to_int64() * 65536L,
          self.host.journal.max_records.to_int64(),
          operations,
        ) {
        Ok(fresh) if fresh == (entries == 0) => ()
        Ok(_) => return Err(CustodyLost)
        Err(@sqlite.CapacityExceeded) => return Err(CapacityExceeded)
        Err(issue) => return Err(Physical(issue))
      }
      // The same entry already admitted both permission tuples and selected
      // policy. Pure preimage construction consumes those unchanged facts.
      let bodies = match
        self.read_admission_preimages(original, facts, actual_policy_cid) {
        Ok(value) => value
        Err(issue) => {
          authority_refusal = Some(issue)
          return Err(AuthorizationDenied)
        }
      }
      let packet = match
        local_read_evidence_packet(
          original,
          bodies,
          request_wire=Some(request_wire),
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        read_client_journal_value(
          self.host.database,
          "client_local_read_evidence",
          bodies.egress.cid,
          reads,
        ) {
        Ok(row) if row.revision == 0L && row.body == packet => ()
        Ok(_) => return Err(CustodyLost)
        Err(@sqlite.NotFound) => {
          if !local_journal_related_append_available(
              count,
              self.host.journal.max_records,
            ) ||
            entries >= 64 ||
            packet.length() > 65536 - used_bytes {
            return Err(CapacityExceeded)
          }
          match
            insert_client_journal_value(
              self.host.database,
              "client_local_read_evidence",
              bodies.egress.cid,
              packet,
              operations,
            ) {
            Ok(_) => ()
            Err(issue) => return Err(Physical(issue))
          }
          match
            compare_exchange_client_journal_value(
              self.host.database,
              "client_local_read_custody",
              "issued",
              revision,
              @utf8.encode((count + 1).to_string()),
              operations,
            ) {
            Ok(_) => ()
            Err(issue) => return Err(Physical(issue))
          }
        }
        Err(issue) => return Err(Physical(issue))
      }
      // Original metadata mutation/CAS has no application callback or external
      // dispatch. Keep receiver lifetime without repeating current admission.
      match self.require_receiver(facts) {
        Ok(_) => {
          committed_bodies.val = Some(bodies)
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
    },
    reads~,
  )
  match stored {
    Ok(value) => {
      if committed_bodies.val is Some(bodies) {
        self.remember_read_evidence(original, facts, bodies, value)
      }
      Ok(value)
    }
    Err(issue) => {
      self.forget_read_evidence()
      match issue {
        TransactionUnknown => Err(Journal(TransactionUnknown))
        _ => Err(authority_refusal.unwrap_or(Journal(issue)))
      }
    }
  }
}

///|
// Closed archive inverse shared with completed File verification. No live
// receiver or authority is constructed by decoding these saved fields.
fn local_read_egress_fields(
  wire : String,
) -> Result[@decode.ObjectView, NativeClientRunJournalIssue] {
  local_read_evidence_object(
    @utf8.encode(wire),
    [
      "attempt_id", "authority_scope_cid", "authorization_context_cid", "data_ceiling_cid",
      "domain", "effective_data_policy_cid", "expires_at", "format", "material_generation_cid",
      "max_bytes", "max_uses", "principal_id", "public_index_entry_cid", "purpose",
      "read_original_cid", "result_artifact_cid", "result_definition_cid", "result_manifest_cid",
      "result_name", "run_definition_cid", "sink", "material_receiver_cid", "result_schema_cid",
      "ordering_evidence_cid", "destination_path", "destination_name", "destination_staging_name",
      "destination_parent_device", "destination_parent_inode", "destination_writer_device",
      "destination_writer_inode",
    ],
    16384,
  )
}

///|
// Ordinary disclosure joins only this target's actual reserved holding and
// fixed adoption/issuance anchors. Whole retained-evidence integrity remains
// an explicit audit; unrelated history cannot authorize or block this target.
fn NativeLocalHostConnection::require_retained_read_evidence_target(
  original : NativeLocalHostConnection,
  request : @host.ClientRequestIdentity,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  match original.read_evidence_issuance(reads~) {
    Ok((count, _)) if count > 0 => ()
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  match
    read_client_journal_capacity(
      original.database,
      "client_local_read_evidence",
      @host.client_request_scope_cid(request),
      operations,
    ) {
    Ok(holding) if holding.reserved_bytes == 65536L &&
      holding.reserved_objects == 1L => Ok(())
    Ok(_) | Err(@sqlite.NotFound) => Err(CustodyLost)
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn NativeLocalHostConnection::read_evidence_issuance(
  original : NativeLocalHostConnection,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[(Int, Int64), NativeClientRunJournalIssue] {
  match
    read_client_journal_value(
      original.database,
      "client_local_read_custody",
      "host",
      reads,
    ) {
    Ok(row) if row.revision == 0L && row.body == original.adoption_body => ()
    Ok(_) | Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  let issued = match
    read_client_journal_value(
      original.database,
      "client_local_read_custody",
      "issued",
      reads,
    ) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  local_read_evidence_issuance_count(
    issued.body,
    issued.revision,
    original.journal.max_records,
  ).map(count => (count, issued.revision))
}
