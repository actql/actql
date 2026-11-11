///|
// Immutable originals in the existing private Native journal. These helpers
// are deliberately private until the checked Provider/installation assembly
// supplies its real request. Custody is not a send or credential-use permit.
priv struct NativeLocalGrantOriginal {
  operation_id : String
  operation_cid : String
  intent : Bytes
  request : @host.ClientRequestIdentity
  issuer_selection_cid : String
  grant : NativeLocalOriginalGrant
  initial_issue : Bytes?
}

///|
fn initialize_local_grant_originals(
  database : @sqlite.Database,
  adoption : Bytes,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  for
    table in [
      "client_local_grant_custody", "client_local_grant_originals", "client_local_preparation_target_originals",
      "client_local_signing_result_originals", "client_local_signing_candidate_originals",
    ] {
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
      database, "client_local_grant_originals", bootstrap,
    ) {
    Ok(value) if value.reserved_bytes == 0L && value.reserved_objects == 0L =>
      ()
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  match
    insert_bootstrap_journal_value(
      database, "client_local_grant_custody", "host", adoption, bootstrap,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  insert_bootstrap_journal_value(
    database, "client_local_grant_custody", "issued", b"0", bootstrap,
  )
  .map(_ => ())
  .map_err(issue => Physical(issue))
}

///|
// A user-chosen operation ID remains stable if input changes. Its row key
// therefore cannot turn divergent intent bytes into a second grant operation.
fn local_grant_original_key(
  crypto : @crypto.Library,
  request : @host.ClientRequestIdentity,
  operation_id : String,
) -> Result[String, NativeClientRunJournalIssue] {
  if operation_id.is_empty() ||
    operation_id.length() > 256 ||
    operation_id.contains("\u{0}") {
    return Err(ChangedIntent)
  }
  let body = match
    local_adoption_record([
      ("domain", "actql-native-local-grant-operation-key/0.1"),
      ("operation_id", operation_id),
      ("submission_scope_cid", @host.client_request_scope_cid(request)),
    ]) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  local_adoption_digest(crypto, body).map_err(_ => Encoding)
}

///|
// Resume-original metadata is exercised by custody WBs; installed Preparation
// uses local_owned_grant_original. Keep this private rather than invent a caller.
#warnings("-unused_value")
fn local_grant_original(
  crypto : @crypto.Library,
  operation_id : String,
  request : @host.ClientRequestIdentity,
  issuer_selection_cid : String,
  grant : @credential.LocalCredentialGrant,
) -> Result[NativeLocalGrantOriginal, NativeClientRunJournalIssue] {
  local_owned_grant_original(
    crypto,
    operation_id,
    request,
    issuer_selection_cid,
    ResumeGrant(grant),
  )
}

///|
fn local_owned_grant_original(
  crypto : @crypto.Library,
  operation_id : String,
  request : @host.ClientRequestIdentity,
  issuer_selection_cid : String,
  grant : NativeLocalOriginalGrant,
) -> Result[NativeLocalGrantOriginal, NativeClientRunJournalIssue] {
  match local_grant_original_key(crypto, request, operation_id) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let request_wire = match @host.client_request_identity_record_wire(request) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let body = match
    local_adoption_record([
      ("domain", "actql-native-local-grant-operation/0.1"),
      ("grant_cid", local_original_grant_cid(grant)),
      ("issuer_selection_cid", issuer_selection_cid),
      ("operation_id", operation_id),
      ("request", request_wire),
    ]) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let operation_cid = match local_adoption_digest(crypto, body) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  Ok({
    operation_id,
    operation_cid,
    intent: body,
    request,
    issuer_selection_cid,
    grant,
    initial_issue: None,
  })
}

///|
fn local_grant_original_packet(
  original : NativeLocalGrantOriginal,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  let grant = match local_original_grant_json(original.grant) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let intent = @utf8.decode(original.intent) catch { _ => return Err(Encoding) }
  try {
    let writer = @encode.writer(49152, 8, 2)
    @encode.begin_object(writer)
    for (key, value) in [("grant", grant), ("intent", intent)] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    if original.grant is PreparationGrant(value) {
      @encode.key(writer, "preparation_fence")
      @encode.string_value(
        writer,
        @credential.local_preparation_fence_json(
          @credential.local_preparation_credential_grant_scope(value).preparation_fence,
        ),
      )
    }
    if original.grant is SigningGrant(value) {
      @encode.key(writer, "signing_purpose")
      @encode.string_value(
        writer,
        local_signing_installation_purpose(
          @credential.local_signing_credential_grant_scope(value).purpose,
        ),
      )
    }
    if original.initial_issue is Some(packet) {
      guard original.grant is SigningGrant(_) else { return Err(CustodyLost) }
      @encode.key(writer, "initial_issue")
      @encode.string_value(writer, @utf8.decode(packet))
    }
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
fn read_local_grant_original(
  crypto : @crypto.Library,
  row : @sqlite.NativeJournalEntry,
) -> Result[NativeLocalGrantOriginal, NativeClientRunJournalIssue] {
  if row.revision != 0L {
    return Err(CustodyLost)
  }
  // Reuse the existing finite value-preserving Native custody decoder.
  let packet = match local_grant_packet_object(row.body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard epoch_text(packet, "grant") is Some(grant_wire) &&
    epoch_text(packet, "intent") is Some(intent_wire) else {
    return Err(CustodyLost)
  }
  let fields = match
    local_adoption_fields(@utf8.encode(intent_wire), [
      "domain", "grant_cid", "issuer_selection_cid", "operation_id", "request",
    ]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if fields[0] != "actql-native-local-grant-operation/0.1" {
    return Err(CustodyLost)
  }
  let request = match
    @host.admit_client_request_identity_record_wire(fields[4]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let grant = match
    local_original_grant_from_packet(crypto, packet, grant_wire, fields[1]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if grant is PreparationGrant(value) {
    let fence = @credential.local_preparation_fence_fields(
      @credential.local_preparation_credential_grant_scope(value).preparation_fence,
    )
    if fence.client_request_intent_cid !=
      @host.client_request_intent_cid(request) ||
      fence.client_request_scope_cid != @host.client_request_scope_cid(request) {
      return Err(CustodyLost)
    }
  }
  if grant is SigningGrant(value) &&
    !local_signing_grant_matches_request(value, request) {
    return Err(CustodyLost)
  }
  let decoded = match
    local_owned_grant_original(crypto, fields[3], request, fields[2], grant) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let original = match @decode.lookup(packet, "initial_issue") {
    None => decoded
    Some(_) => {
      guard decoded.grant is SigningGrant(_) &&
        epoch_text(packet, "initial_issue") is Some(wire) else {
        return Err(CustodyLost)
      }
      { ..decoded, initial_issue: Some(@utf8.encode(wire)), }
    }
  }
  guard local_grant_original_key(crypto, request, fields[3]) is Ok(key) &&
    key == row.key &&
    original.intent == @utf8.encode(intent_wire) &&
    local_grant_original_packet(original) is Ok(exact_packet) &&
    exact_packet == row.body else {
    return Err(CustodyLost)
  }
  Ok(original)
}

///|
fn NativeLocalHostConnection::local_grant_custody(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[(Int, Int64, Map[String, (Int, Int)]), NativeClientRunJournalIssue] {
  guard self.database.scan_after("client_local_grant_custody", "") is Ok(host) &&
    host.key == "host" &&
    host.revision == 0L &&
    host.body == self.adoption_body &&
    self.database.scan_after("client_local_grant_custody", "host") is Ok(issued) &&
    issued.key == "issued" &&
    self.database.scan_after("client_local_grant_custody", "issued")
    is Err(@sqlite.NotFound) else {
    return Err(CustodyLost)
  }
  let count = match
    local_journal_related_issuance_count(
      issued.body,
      issued.revision,
      self.journal.max_records,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let runs : Map[String, (Int, Int)] = Map([])
  let mut cursor = ""
  let mut observed = 0
  let mut signing_results = 0
  let mut signing_candidates = 0
  while true {
    let row = match
      self.database.scan_after("client_local_grant_originals", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    if observed >= count {
      return Err(CustodyLost)
    }
    observed += 1
    let original = match read_local_grant_original(crypto, row) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let scope = local_original_grant_facts(original.grant)
    let retained_run = match self.journal.retained(original.request) {
      Ok(Some(value)) =>
        @publication.publication_contract_identity(value.definition)
      Ok(None) | Err(_) => return Err(CustodyLost)
    }
    guard scope.host_adoption_cid == self.adoption_cid &&
      scope.account_configuration_cid ==
      self.session.configuration.configuration_cid() &&
      scope.account_id == self.session.configuration.account_id() else {
      return Err(CustodyLost)
    }
    if original.grant is SigningGrant(grant) {
      let checked = if original.initial_issue is Some(_) {
        self.check_initial_signing_grant_original_locked(
          original,
          retained_run,
          capture~,
        )
      } else {
        self.check_signing_grant_original_locked(
          grant,
          original.request,
          retained_run,
        )
      }
      match checked {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    } else if scope.submission_scope_cid !=
      @host.client_request_scope_cid(original.request) ||
      scope.authority_scope_cid !=
      @host.client_request_authority_scope_cid(original.request) {
      return Err(CustodyLost)
    }
    if original.initial_issue is None {
      guard self.session.settings.files
        .iter()
        .find_first(file => file.content_cid == original.issuer_selection_cid)
        is Some(file) else {
        return Err(CustodyLost)
      }
      let selection = match
        admit_native_local_credential_issuer_selection(
          @utf8.decode(file.body) catch {
            _ => return Err(CustodyLost)
          },
        ) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      if (
          !(original.grant is SigningGrant(_)) &&
          scope.principal != selection.principal
        ) ||
        !local_original_grant_matches_issuer(original.grant, selection) {
        return Err(CustodyLost)
      }
    }
    let reservation = local_original_grant_reservation_scope(original)
    let (entries, bytes) = runs.get(reservation).unwrap_or((0, 0))
    let mut result_bytes = 0
    if original.grant is SigningGrant(grant) &&
      original.initial_issue is Some(_) &&
      @credential.local_signing_credential_grant_scope(grant).purpose ==
      @credential.HostAttestation {
      let prepared = match local_initial_host_prepared_locked(self, original) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      result_bytes += prepared.length()
      signing_candidates += 1
    }
    match
      self.database.read(
        "client_local_signing_result_originals",
        original.operation_cid,
      ) {
      Err(@sqlite.NotFound) => ()
      Err(issue) => return Err(Physical(issue))
      Ok(result) => {
        guard original.grant is SigningGrant(_) else { return Err(CustodyLost) }
        let history = match
          local_initial_signing_original_history_locked(self, original) {
          Ok(value) if value.observed_outcome() ==
            @credential_resource.Succeeded => value
          _ => return Err(CustodyLost)
        }
        let (_, candidate) = match
          local_initial_resolution_result_locked(
            self,
            original,
            history.original_use(),
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        result_bytes += result.body.length() +
          candidate.map(wire => @utf8.encode(wire).length()).unwrap_or(0)
        signing_results += 1
        if candidate is Some(_) {
          signing_candidates += 1
        }
      }
    }
    if entries >= 64 || row.body.length() + result_bytes > 65536 - bytes {
      return Err(CustodyLost)
    }
    runs[reservation] = (entries + 1, bytes + row.body.length() + result_bytes)
    if runs.length() > self.journal.max_records {
      return Err(CustodyLost)
    }
    cursor = row.key
  }
  // No orphan result or wire may escape the existing immutable grant bucket.
  for
    (table, expected) in [
      ("client_local_signing_result_originals", signing_results),
      ("client_local_signing_candidate_originals", signing_candidates),
    ] {
    let mut after = ""
    let mut found = 0
    while true {
      match self.database.scan_after(table, after) {
        Err(@sqlite.NotFound) => break
        Err(issue) => return Err(Physical(issue))
        Ok(row) => {
          found += 1
          if found > expected {
            return Err(CustodyLost)
          }
          after = row.key
        }
      }
    }
    if found != expected {
      return Err(CustodyLost)
    }
  }
  // Optional old target absence is not repaired. Every retained target row
  // must instead have an immutable original Preparation grant in this bucket.
  let mut target_cursor = ""
  let mut targets = 0
  while true {
    let row = match
      self.database.scan_after(
        "client_local_preparation_target_originals", target_cursor,
      ) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    targets += 1
    if targets > count {
      return Err(CustodyLost)
    }
    let grant_row = match
      self.database.read("client_local_grant_originals", row.key) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    let original = match
      read_local_grant_original(crypto, {
        key: row.key,
        body: grant_row.body,
        revision: grant_row.revision,
      }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let target = match
      read_local_preparation_target_record(self, original, row) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !self.session.settings.files.any(file => {
        file.name == target.provider_file_name &&
        file.content_cid == target.provider_selection_cid
      }) {
      return Err(CustodyLost)
    }
    let scope = @host.client_request_scope_cid(original.request)
    guard runs.get(scope) is Some((entries, bytes)) &&
      row.body.length() <= 65536 - bytes else {
      return Err(CustodyLost)
    }
    runs[scope] = (entries, bytes + row.body.length())
    target_cursor = row.key
  }
  guard observed == count &&
    self.database.capacity_usage("client_local_grant_originals") is Ok(usage) &&
    usage.reserved_objects == runs.length().to_int64() &&
    usage.reserved_bytes == runs.length().to_int64() * 65536L else {
    return Err(CustodyLost)
  }
  // The existing exact reservation operation is non-mutating for retained
  // matches. A fresh result here means custody loss; the caller's journal
  // transaction rolls back, so lookup cannot persist a replacement reservation.
  for scope in runs.keys() {
    match
      self.database.reserve_capacity_in_transaction(
        "client_local_grant_originals",
        scope,
        65536L,
        1L,
        self.journal.max_records.to_int64() * 65536L,
        self.journal.max_records.to_int64(),
      ) {
      Ok(false) => ()
      Ok(true) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok((count, issued.revision, runs))
}

///|
// Called only after trusted assembly admits the actual checked Provider
// request and installation. It does not issue/use a grant or authorize I/O.
// The current opaque resume claim is checked inside the same transaction as
// immutable custody. Entered/unknown rows cannot receive a renewed grant here.
// The original Resume claim/current/append path remains private until the
// installed issuer supplies real custody. Unused does not authorize installation.
#warnings("-unused_value")
fn NativeLocalCredentialIssuerBinding::retain_grant_original(
  self : NativeLocalCredentialIssuerBinding,
  original : NativeLocalGrantOriginal,
  claim : NativeClientEffectResumeClaim,
) -> Result[Unit, NativeClientRunJournalIssue] {
  self.host.journal.transaction(() => {
    if self.require_current(self.host, original.operation_cid) is Err(_) {
      return Err(AuthorizationDenied)
    }
    guard original.grant is ResumeGrant(grant) else {
      return Err(AuthorizationDenied)
    }
    let scope = @credential.local_credential_grant_scope(grant)
    let now = @env.now().reinterpret_as_int64()
    let expected_grant = match
      @credential.prepare_local_credential_grant(
        self.selection.issuer_authority,
        scope,
        @values.timestamp_epoch_milliseconds(self.selection.expires_at).unwrap(),
        self.selection.max_uses,
      ) {
      Ok(value) => value
      Err(_) => return Err(ChangedIntent)
    }
    guard @credential.local_credential_grant_cid(expected_grant) ==
      local_original_grant_cid(original.grant) &&
      local_owned_grant_original(
        self.crypto,
        original.operation_id,
        original.request,
        original.issuer_selection_cid,
        original.grant,
      )
      is Ok(exact) &&
      exact.operation_cid == original.operation_cid &&
      exact.intent == original.intent else {
      return Err(ChangedIntent)
    }
    guard self.host.journal.effect_resume_fence_locked(claim, now)
      is Ok(Current) &&
      @host.client_request_identity_relation(original.request, claim.request)
      is @host.SameRequest &&
      scope.fence_intent_cid == claim.intent_id &&
      scope.fence_claimant == claim.claim.claimant &&
      scope.fence_generation == claim.claim.generation &&
      scope.host_adoption_cid == self.host.adoption_cid &&
      scope.authority_scope_cid == self.scope &&
      scope.submission_scope_cid ==
      @host.client_request_scope_cid(original.request) &&
      scope.account_configuration_cid ==
      self.host.session.configuration.configuration_cid() &&
      scope.account_id == self.host.session.configuration.account_id() &&
      scope.principal == self.principal &&
      original.issuer_selection_cid == self.file.content_cid &&
      local_original_grant_limits(original.grant) ==
      (
        self.selection.max_uses,
        @values.timestamp_epoch_milliseconds(self.selection.expires_at).unwrap(),
      ) else {
      return Err(AuthorizationDenied)
    }
    let record = match self.host.journal.retained(original.request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    guard record.checkpoint is Some(checkpoint) else { return Err(CustodyLost) }
    // A caller cannot create a fresh grant for a possibly-sent original row.
    if checkpoint.effect_ledger.any(entry => {
        entry.canonical_request_cid == scope.request_cid &&
        @effect.effect_ledger_entry_state_code(entry) != 0
      }) {
      return Err(Checkpoint(NeedsOriginalContinuation))
    }
    self.append_grant_original_locked(original, () => {
      if self.require_current(self.host, original.operation_cid) is Err(_) {
        return Err(AuthorizationDenied)
      }
      match
        self.host.journal.effect_resume_fence_locked(
          claim,
          @env.now().reinterpret_as_int64(),
        ) {
        Ok(Current) => Ok(())
        Ok(_) => Err(AuthorizationDenied)
        Err(issue) => Err(issue)
      }
    })
  })
}

///|
// Read-only original-operation reconciliation. Absence is unresolved, never
// permission to issue again; corrupt originals/reservations are not rebuilt.
fn NativeLocalCredentialIssuerBinding::lookup_grant_original(
  self : NativeLocalCredentialIssuerBinding,
  reference : NativeLocalGrantOriginal,
) -> Result[NativeLocalGrantOriginal?, NativeClientRunJournalIssue] {
  if reference.grant is SigningGrant(_) {
    return Err(AuthorizationDenied)
  }
  self.host.journal.transaction(() => {
    if self.require_current(self.host, self.operation_cid) is Err(_) {
      return Err(AuthorizationDenied)
    }
    guard local_owned_grant_original(
        self.crypto,
        reference.operation_id,
        reference.request,
        reference.issuer_selection_cid,
        reference.grant,
      )
      is Ok(exact) &&
      exact.operation_cid == self.operation_cid &&
      exact.operation_cid == reference.operation_cid &&
      exact.intent == reference.intent &&
      reference.issuer_selection_cid == self.file.content_cid else {
      return Err(ChangedIntent)
    }
    let request = reference.request
    if @host.client_request_authority_scope_cid(request) != self.scope {
      return Err(ForeignRun)
    }
    self.host.lookup_local_grant_original_locked(self.crypto, reference)
  })
}

///|
// Shared custody read under the existing Run journal transaction. Authorization
// remains with the calling issuer or raw-read operation, not this record reader.
fn NativeLocalHostConnection::lookup_local_grant_original_locked(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  reference : NativeLocalGrantOriginal,
) -> Result[NativeLocalGrantOriginal?, NativeClientRunJournalIssue] {
  let request = reference.request
  match self.journal.retained(request) {
    Ok(Some(_)) => ()
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  match self.local_grant_custody(crypto) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = match
    local_grant_original_key(crypto, request, reference.operation_id) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let row = match self.database.read("client_local_grant_originals", key) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok(None)
    Err(issue) => return Err(Physical(issue))
  }
  let original = match
    read_local_grant_original(crypto, {
      key,
      body: row.body,
      revision: row.revision,
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if original.operation_cid != reference.operation_cid ||
    original.issuer_selection_cid != reference.issuer_selection_cid ||
    original.intent != reference.intent {
    return Err(ChangedIntent)
  }
  Ok(Some(original))
}

///|
// Caller holds the existing Run journal transaction and has admitted its
// variant-specific operational fence. All grant variants share this bounded
// immutable append, issuance witness and exact per-Run reservation.
fn NativeLocalCredentialIssuerBinding::append_grant_original_locked(
  self : NativeLocalCredentialIssuerBinding,
  original : NativeLocalGrantOriginal,
  current : () -> Result[Unit, NativeClientRunJournalIssue],
  target? : NativeLocalPreparationOriginalTarget? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if original.grant is SigningGrant(_) {
    return Err(AuthorizationDenied)
  }
  self.append_owned_grant_original_locked(original, current, target~)
}

///|
// Variant-specific opaque callers establish their own operational fence. This
// is the same immutable append/counter/reservation Owner, not another issuer.
fn NativeLocalCredentialIssuerBinding::append_owned_grant_original_locked(
  self : NativeLocalCredentialIssuerBinding,
  original : NativeLocalGrantOriginal,
  current : () -> Result[Unit, NativeClientRunJournalIssue],
  target? : NativeLocalPreparationOriginalTarget? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  append_local_owned_grant_original_locked(
    self.host,
    self.crypto,
    original,
    current,
    target~,
  )
}
