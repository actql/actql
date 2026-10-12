///|
// Slash is forbidden in selected basenames, so this closed installation role
// cannot shadow any original file. It shares the existing settings capacity.
let local_policy_upgrade_key = "policy-upgrade/0.1"

///|
priv struct NativeLocalPolicyUpgradeOriginal {
  packet : Bytes
  body : Bytes
  original : @host.ClientLocalRunPolicyUpgrade
  profile : @host.ClientLocalRunPolicyProfile
  files : Array[NativeLocalSelectedFile]
  principal : String
  connection : String
  scope : String
  operation_id : String
}

///|
pub(all) struct NativeLocalPolicyUpgradeReceipt {
  operation_id : String
  adoption_cid : String
  authority_scope_cid : String
  original_cid : String
  profile_cid : String
}

///|
fn local_policy_upgrade_current(
  host : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  scope : String,
  append : Bool,
) -> Bool {
  if !(host.authority_scope_cid(principal, connection, crypto) is Ok(current) &&
    current == scope) {
    return false
  }
  for
    operation in (if append { ["submit", "publish", "read"] } else { ["read"] }) {
    if !(host.authorize({ principal, connection, resource: "run", operation, })
      is Ok(@authorization.Allow(_))) {
      return false
    }
  }
  true
}

///|
// Existing private epoch authenticity, with this closed payload role. Split
// base64 obeys the original 4096-string/8192-wire codec bounds. No key is issued.
fn local_policy_upgrade_packet(
  host : NativeLocalHostConnection,
  payload : Bytes,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  if payload.length() > 5632 {
    return Err(CapacityExceeded)
  }
  let (key, _, _) = match read_epoch_custody(host.database) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(issue))
  }
  let tag = match host.epoch.crypto.hmac_sha256(key, payload) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let encoded = @base64.encode(payload)
  let split = encoded.length().min(4096)
  @host.client_local_original_record_body([
    ("payload_head", encoded[:split].to_owned()),
    ("payload_tail", encoded[split:].to_owned()),
    ("tag", epoch_hex(tag)),
  ]).map_err(_ => CapacityExceeded)
}

///|
fn local_policy_upgrade_payload(
  host : NativeLocalHostConnection,
  packet : Bytes,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  let fields = match
    @host.client_local_original_record_fields(packet, [
      "payload_head", "payload_tail", "tag",
    ]) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let encoded = fields[0] + fields[1]
  if encoded.length() > 7512 || fields[0].length() != encoded.length().min(4096) {
    return Err(CustodyLost)
  }
  let payload = @base64.decode(encoded) catch { _ => return Err(CustodyLost) }
  guard payload.length() <= 5632 &&
    @base64.encode(payload) == encoded &&
    epoch_hex_bytes(fields[2]) is Some(tag) else {
    return Err(CustodyLost)
  }
  let (key, _, _) = match read_epoch_custody(host.database) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(issue))
  }
  guard host.epoch.crypto.verify_hmac_sha256(key, payload, tag) is Ok(true) else {
    return Err(CustodyLost)
  }
  Ok(payload)
}

///|
fn read_local_policy_upgrade_original(
  host : NativeLocalHostConnection,
  row : @sqlite.NativeJournalValue,
) -> Result[NativeLocalPolicyUpgradeOriginal, NativeClientRunJournalIssue] {
  if row.revision != 0L {
    return Err(CustodyLost)
  }
  let body = match local_policy_upgrade_payload(host, row.body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let keys = [
    "adoption_cid", "authority_scope_cid", "legacy_admissions_wire", "operation_id",
    "profile_wire", "read_configuration_name", "read_original_cid", "read_selection_wire",
    "retention_configuration_cid", "retention_configuration_name", "run_configuration_cid",
    "run_configuration_name", "store_configuration_cid", "store_configuration_name",
    "version",
  ]
  let (fields, runtime) = match
    @host.client_local_original_record_fields(body, keys) {
    Ok(value) => (value, false)
    Err(_) => {
      let runtime_keys = keys.copy()
      runtime_keys.insert(12, "runtime_pair_wire")
      let value = match
        @host.client_local_original_record_fields(body, runtime_keys) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let original_fields = value.copy()
      ignore(original_fields.remove(12))
      original_fields[14] = "actql-local-run-policy-upgrade/0.1"
      (original_fields, true)
    }
  }
  let files : Array[NativeLocalSelectedFile] = []
  for name in [fields[5], fields[11], fields[9], fields[13]] {
    match local_run_policy_selected(host, name) {
      Ok(file) => files.push(file)
      Err(issue) => return Err(issue)
    }
  }
  let read_text = @utf8.decode(files[0].body) catch {
    _ => return Err(CustodyLost)
  }
  let selection = match admit_native_local_read_selection(read_text) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard selection.expiry is Absolute(_) else { return Err(CustodyLost) }
  let common = match
    local_run_policy_common_originals(
      host.session.source_body,
      files[1].body,
      files[2].body,
      files[3].body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let profile = match
    @host.admit_client_local_run_policy_profile(fields[4], common) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let scope = match
    host.authority_scope_cid(
      selection.principal,
      selection.connection,
      host.epoch.crypto,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let original = if runtime {
    let pair = match host.runtime_policy_pair(scope) {
      Ok(Some(value)) => value
      _ => return Err(CustodyLost)
    }
    match
      @host.admit_client_local_runtime_policy_upgrade(
        body,
        profile,
        read_text,
        host.adoption_cid,
        scope,
        fields[3],
        files.map(file => (file.name, file.content_cid)),
        pair,
      ) {
      Ok(value) => @host.client_local_runtime_policy_upgrade_policy(value)
      Err(_) => return Err(CustodyLost)
    }
  } else {
    match
      @host.admit_client_local_run_policy_upgrade(
        body,
        profile,
        read_text,
        host.adoption_cid,
        scope,
        fields[3],
        files.map(file => (file.name, file.content_cid)),
      ) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
  }
  let finite = match
    admit_native_local_read_selection(
      @host.client_local_run_policy_upgrade_read_wire(original),
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard finite.expiry is AcceptedRunProfile(roles) &&
    roles.profile_cid == @host.client_local_run_policy_profile_cid(profile) &&
    roles.run_file == files[1].name &&
    roles.retention_file == files[2].name &&
    roles.store_file == files[3].name else {
    return Err(CustodyLost)
  }
  Ok({
    packet: row.body,
    body,
    original,
    profile,
    files,
    principal: selection.principal,
    connection: selection.connection,
    scope,
    operation_id: fields[3],
  })
}

///|
// Capture only immutable accepted facts in this actor's scope. Current Run
// state is not frozen, and another principal's history is not exposed.
fn local_policy_legacy_admissions(
  host : NativeLocalHostConnection,
  scope : String,
) -> Result[
  Array[@host.ClientLocalLegacyPolicyRun],
  NativeClientRunJournalIssue,
] {
  match host.journal.submitted_intent_custody() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let records : Array[@host.ClientLocalLegacyPolicyRun] = []
  let mut cursor = ""
  let mut count = 0
  while true {
    let row = match
      host.database.scan_after("client_submitted_intents", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    count += 1
    if count > host.journal.max_records {
      return Err(CustodyLost)
    }
    let decoded = match @host.decode_client_submitted_journal_row(row.body) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    let reference = native_submission_reference_record(decoded.reference)
    let original = match host.journal.retained_submission(reference) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    if original.run_admission is Some(admission) &&
      @host.client_request_authority_scope_cid(admission.request) == scope {
      let run = match host.journal.retained(admission.request) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if run.local_run_policy_originals is Some(_) {
        return Err(ChangedIntent)
      }
      let reference_cid = match
        local_adoption_digest(
          host.epoch.crypto,
          @utf8.encode(original.reference.wire),
        ) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      if records.length() == 8 {
        return Err(CapacityExceeded)
      }
      records.push({
        request_scope_cid: @host.client_request_scope_cid(admission.request),
        run_definition_cid: admission.run_definition_cid,
        submission_reference_cid: reference_cid,
        admitted_revision: admission.revision,
      })
    }
    cursor = row.key
  }
  Ok(records)
}

///|
fn local_policy_upgrade_receipt(
  host : NativeLocalHostConnection,
  original : NativeLocalPolicyUpgradeOriginal,
) -> Result[NativeLocalPolicyUpgradeReceipt, NativeClientRunJournalIssue] {
  let cid = match local_adoption_digest(host.epoch.crypto, original.body) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  Ok({
    operation_id: original.operation_id,
    adoption_cid: host.adoption_cid,
    authority_scope_cid: original.scope,
    original_cid: cid,
    profile_cid: @host.client_local_run_policy_profile_cid(original.profile),
  })
}

///|
/// Explicit bounded upgrade, not Run submission or an authority grant. The
/// original adoption/config/files remain unchanged. Same operation reuses the
/// immutable append; another operation cannot borrow its successful result.
pub fn NativeLocalHostConnection::upgrade_run_policy(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  operation_id : String,
  read_file : String,
  run_file : String,
  retention_file : String,
  store_file : String,
) -> Result[NativeLocalPolicyUpgradeReceipt, NativeClientRunJournalIssue] {
  if operation_id.is_empty() ||
    operation_id.length() > 128 ||
    operation_id.contains("\u{0000}") {
    return Err(InvalidSubmission)
  }
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let current = () => {
    local_policy_upgrade_current(
      self, crypto, principal, connection, scope, true,
    )
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.journal.transaction(() => {
    if !current() {
      return Err(AuthorizationDenied)
    }
    let (count, revision) = match self.installation_custody() {
      Ok(value) => value
      Err(issue) => return Err(local_policy_upgrade_custody_issue(issue))
    }
    match
      self.database.read(
        "client_local_installation_originals", local_policy_upgrade_key,
      ) {
      Ok(row) => {
        let existing = match read_local_policy_upgrade_original(self, row) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        let pair = match self.runtime_policy_pair(scope) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if pair is Some(_) &&
          @host.client_local_original_record_fields(existing.body, [
            "adoption_cid", "authority_scope_cid", "legacy_admissions_wire", "operation_id",
            "profile_wire", "read_configuration_name", "read_original_cid", "read_selection_wire",
            "retention_configuration_cid", "retention_configuration_name", "run_configuration_cid",
            "run_configuration_name", "runtime_pair_wire", "store_configuration_cid",
            "store_configuration_name", "version",
          ])
          is Err(_) {
          return Err(ChangedIntent)
        }
        if existing.scope != scope {
          return Err(AuthorizationDenied)
        }
        if existing.operation_id != operation_id ||
          existing.files.map(file => file.name) !=
          [read_file, run_file, retention_file, store_file] {
          return Err(ChangedIntent)
        }
        if !current() {
          return Err(AuthorizationDenied)
        }
        return local_policy_upgrade_receipt(self, existing)
      }
      Err(@sqlite.NotFound) => ()
      Err(issue) => return Err(Physical(issue))
    }
    if count >= 8 {
      return Err(CapacityExceeded)
    }
    // Reserve before copying any append material. Rollback retains the original
    // counter and custody if a later validation, encoding or commit fails.
    match
      self.database.reserve_capacity_in_transaction(
        "client_local_settings",
        "installation:" + local_policy_upgrade_key,
        8192L,
        1L,
        65536L,
        8L,
      ) {
      Ok(true) => ()
      Ok(false) => return Err(CustodyLost)
      Err(@sqlite.CapacityExceeded) => return Err(CapacityExceeded)
      Err(issue) => return Err(Physical(issue))
    }
    let files : Array[NativeLocalSelectedFile] = []
    for name in [read_file, run_file, retention_file, store_file] {
      match local_run_policy_selected(self, name) {
        Ok(file) => files.push(file)
        Err(issue) => return Err(issue)
      }
    }
    let read_text = @utf8.decode(files[0].body) catch {
      _ => return Err(CustodyLost)
    }
    guard admit_native_local_read_selection(read_text) is Ok(selection) &&
      selection.expiry is Absolute(_) &&
      selection.principal == principal &&
      selection.connection == connection else {
      return Err(ChangedIntent)
    }
    let common = match
      local_run_policy_common_originals(
        self.session.source_body,
        files[1].body,
        files[2].body,
        files[3].body,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let profile = match @host.client_local_run_policy_profile(common) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    let legacy = match local_policy_legacy_admissions(self, scope) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let original = match
      @host.bind_client_local_run_policy_upgrade(
        profile,
        read_text,
        self.adoption_cid,
        scope,
        operation_id,
        files.map(file => (file.name, file.content_cid)),
        legacy,
      ) {
      Ok(value) => value
      Err(_) => return Err(Encoding)
    }
    // The same reserved append contains the immutable runtime correspondence.
    // An old fifteen-key append is never repaired/backfilled on restore.
    let body = match self.runtime_policy_pair(scope) {
      Err(issue) => return Err(issue)
      Ok(None) => @host.client_local_run_policy_upgrade_body(original)
      Ok(Some(pair)) =>
        match @host.bind_client_local_runtime_policy_upgrade(original, pair) {
          Ok(value) => @host.client_local_runtime_policy_upgrade_body(value)
          Err(_) => return Err(Encoding)
        }
    }
    if body.length() > 5632 {
      return Err(CapacityExceeded)
    }
    let packet = match local_policy_upgrade_packet(self, body) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !current() {
      return Err(AuthorizationDenied)
    }
    match
      self.database.insert(
        "client_local_installation_originals", local_policy_upgrade_key, packet,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
    match
      self.database.compare_exchange(
        "client_local_installation_custody",
        "issued",
        revision,
        @utf8.encode((count + 1).to_string()),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
    if !current() {
      return Err(AuthorizationDenied)
    }
    let saved = match
      read_local_policy_upgrade_original(self, { body: packet, revision: 0L, }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    local_policy_upgrade_receipt(self, saved)
  })
}

///|
/// Exact original operation lookup. No append, Policy issuance, grant, Store
/// open, start or external operation is reachable, including after ACK loss.
pub fn NativeLocalHostConnection::lookup_run_policy_upgrade(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  operation_id : String,
) -> Result[NativeLocalPolicyUpgradeReceipt?, NativeClientRunJournalIssue] {
  if operation_id.is_empty() ||
    operation_id.length() > 128 ||
    operation_id.contains("\u{0000}") {
    return Err(InvalidSubmission)
  }
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let current = () => {
    local_policy_upgrade_current(
      self, crypto, principal, connection, scope, false,
    )
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.journal.transaction(() => {
    if !current() {
      return Err(AuthorizationDenied)
    }
    match self.installation_custody() {
      Ok(_) => ()
      Err(_) => return Err(CustodyLost)
    }
    let existing = match
      self.database.read(
        "client_local_installation_originals", local_policy_upgrade_key,
      ) {
      Ok(row) => {
        let value = match read_local_policy_upgrade_original(self, row) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if value.scope != scope {
          return Err(AuthorizationDenied)
        }
        if value.operation_id != operation_id {
          return Err(ChangedIntent)
        }
        Some(value)
      }
      Err(@sqlite.NotFound) => None
      Err(issue) => return Err(Physical(issue))
    }
    if !current() {
      return Err(AuthorizationDenied)
    }
    match existing {
      None => Ok(None)
      Some(value) =>
        local_policy_upgrade_receipt(self, value).map(value => Some(value))
    }
  })
}

///|
// The original installation counter/reservations prove absence or presence;
// missing custody is never interpreted as an un-upgraded legacy installation.
fn NativeLocalHostConnection::retained_policy_upgrade(
  self : NativeLocalHostConnection,
) -> Result[NativeLocalPolicyUpgradeOriginal?, NativeClientRunJournalIssue] {
  match self.with_installation_custody(() => Ok(())) {
    Ok(_) => ()
    Err(_) => return Err(CustodyLost)
  }
  match
    self.database.read(
      "client_local_installation_originals", local_policy_upgrade_key,
    ) {
    Ok(row) =>
      read_local_policy_upgrade_original(self, row).map(value => Some(value))
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn NativeLocalHostConnection::require_original_legacy_policy(
  self : NativeLocalHostConnection,
  request : @host.ClientRequestIdentity,
) -> Result[Unit, NativeClientRunJournalIssue] {
  self.with_installation_custody(() => {
    self.require_original_legacy_policy_locked(request)
  })
}

///|
// Join only this physical journal's existing transaction. Outside it, the same
// Owner opens the bounded transaction; missing reservations roll back instead
// of being silently retained. No caller-supplied flag permits a join.
fn[T] NativeLocalHostConnection::with_installation_custody(
  self : NativeLocalHostConnection,
  work : () -> Result[T, NativeClientRunJournalIssue],
) -> Result[T, NativeClientRunJournalIssue] {
  if self.journal.fenced || self.database.transaction_fenced() {
    return Err(Fenced)
  }
  let checked = () => {
    match self.installation_custody() {
      Ok(_) => work()
      Err(issue) => Err(local_policy_upgrade_custody_issue(issue))
    }
  }
  if self.journal.transaction_active {
    checked()
  } else {
    self.journal.transaction(checked)
  }
}

///|
fn NativeLocalHostConnection::require_original_legacy_policy_locked(
  self : NativeLocalHostConnection,
  request : @host.ClientRequestIdentity,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let upgrade = match self.retained_policy_upgrade() {
    Ok(None) => return Ok(())
    Ok(Some(value)) => value
    Err(issue) => return Err(issue)
  }
  if @host.client_request_authority_scope_cid(request) != upgrade.scope {
    return Err(AuthorizationDenied)
  }
  let current = () => {
    local_policy_upgrade_current(
      self,
      self.epoch.crypto,
      upgrade.principal,
      upgrade.connection,
      upgrade.scope,
      false,
    )
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  let expected = @host.client_local_run_policy_upgrade_legacy_runs(
      upgrade.original,
    )
    .iter()
    .find_first(record => {
      record.request_scope_cid == @host.client_request_scope_cid(request)
    })
  guard expected is Some(expected) else { return Err(CustodyLost) }
  let run = match self.journal.retained(request) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  if run.local_run_policy_originals is Some(_) ||
    expected.run_definition_cid !=
    @publication.publication_contract_identity(run.definition) {
    return Err(CustodyLost)
  }
  // The legacy set contains reference CIDs, never another Run's current state.
  let mut cursor = ""
  let mut seen = 0
  while true {
    let row = match
      self.database.scan_after("client_submitted_intents", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
    seen += 1
    if seen > self.journal.max_records {
      return Err(CustodyLost)
    }
    let decoded = match @host.decode_client_submitted_journal_row(row.body) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    let reference = native_submission_reference_record(decoded.reference)
    if local_adoption_digest(self.epoch.crypto, @utf8.encode(reference.wire))
      is Ok(cid) &&
      cid == expected.submission_reference_cid {
      match
        self.journal.verify_submission_locked(
          self.epoch,
          reference,
          upgrade.scope,
          current(),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      guard self.journal.retained_submission(reference) is Ok(Some(original)) &&
        original.run_admission is Some(admission) &&
        admission.revision == expected.admitted_revision &&
        @host.client_request_identity_relation(admission.request, request) ==
        @host.SameRequest &&
        admission.run_definition_cid == expected.run_definition_cid else {
        return Err(CustodyLost)
      }
      if !current() {
        return Err(AuthorizationDenied)
      }
      return Ok(())
    }
    cursor = row.key
  } nobreak {
    Err(CustodyLost)
  }
}

///|
fn policy_binding_from_upgrade(
  host : NativeLocalHostConnection,
  crypto : @crypto.Library,
  upgrade : NativeLocalPolicyUpgradeOriginal,
) -> Result[NativeLocalRunPolicyBinding, NativeClientRunJournalIssue] {
  let wire = @host.client_local_run_policy_upgrade_read_wire(upgrade.original)
  let cid = match local_adoption_digest(crypto, @utf8.encode(wire)) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  Ok({
    host,
    crypto,
    principal: upgrade.principal,
    connection: upgrade.connection,
    scope: upgrade.scope,
    files: upgrade.files,
    read_file: upgrade.files[0],
    run_file: upgrade.files[1],
    retention_file: upgrade.files[2],
    store_file: upgrade.files[3],
    origin: Upgraded(upgrade.packet, wire),
    profile: upgrade.profile,
    read_selection_cid: cid,
  })
}

///|
/// Read the committed upgrade through current Run read; no implicit append is
/// performed. This preserves original selected files rather than faking a file
/// generation for the new, authenticated journal configuration original.
pub fn NativeLocalHostConnection::bind_upgraded_run_policy(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  read_file : String,
  run_file : String,
) -> Result[NativeLocalRunPolicyBinding?, NativeClientRunJournalIssue] {
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let current = () => {
    local_policy_upgrade_current(
      self, crypto, principal, connection, scope, false,
    )
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.journal.transaction(() => {
    if !current() {
      return Err(AuthorizationDenied)
    }
    let upgrade = match self.retained_policy_upgrade() {
      Ok(None) => return Ok(None)
      Ok(Some(value)) => value
      Err(issue) => return Err(issue)
    }
    if upgrade.scope != scope {
      return Err(AuthorizationDenied)
    }
    if upgrade.files[0].name != read_file || upgrade.files[1].name != run_file {
      return Err(ChangedIntent)
    }
    let binding = match policy_binding_from_upgrade(self, crypto, upgrade) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !current() {
      return Err(AuthorizationDenied)
    }
    Ok(Some(binding))
  })
}

///|
fn local_policy_upgrade_custody_issue(
  issue : NativeLocalAdoptionIssue,
) -> NativeClientRunJournalIssue {
  match issue {
    Physical(issue) => Physical(issue)
    Journal(issue) => issue
    Epoch(issue) => Epoch(issue)
    Fenced => Fenced
    TransactionUnknown => TransactionUnknown
    _ => CustodyLost
  }
}
