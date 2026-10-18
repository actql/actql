///|
/// One pre-Core child identity in the existing adoption/journal Owner. Keeping
/// this carrier retains the original installed selection even on write failure.
/// Its key never supplies funding, launch, scoped stop or settlement authority.
struct NativeLocalWorkerProvisioningAttempt {
  host : NativeLocalHostConnection
  selection : @arena.InstalledArenaWorkerSelection
  body : Bytes
  key : String
  mut resource : NativeLocalWorkerResourceOriginal?
}

///|
pub(all) enum NativeLocalWorkerProvisioningIssue {
  Adoption(NativeLocalAdoptionIssue)
  Journal(NativeClientRunJournalIssue)
  Selection(@bootstrap.NativeBootstrapIssue)
  PhysicalSelection(@bootstrap.NativeBackedExecutionIssue)
  AuthorizationDenied
  CustodyLost
}

///|
/// All cold observations are unresolved. A saved identity is not a live child,
/// a resource snapshot, zero debt, physical retirement or permission to retry.
pub(all) enum NativeLocalWorkerProvisioningObservation {
  UnresolvedOriginal(String, Bytes, NativeLocalWorkerRecordObservation)
}

///|
pub(all) enum NativeLocalWorkerRecordObservation {
  NotRecorded
  Recorded
}

///|
fn initialize_local_worker_provisioning(
  database : @sqlite.Database,
  adoption : Bytes,
  crypto : @crypto.Library,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  for
    record_namespace in [
      "client_worker_provisioning_custody", "client_worker_provisioning",
    ] {
    match
      scan_client_journal_value(
        database,
        record_namespace,
        "",
        bootstrap_journal_reads(bootstrap),
      ) {
      Err(@sqlite.NotFound) => ()
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
  }
  let parent = match local_adoption_digest(crypto, adoption) {
    Err(issue) => return Err(issue)
    Ok(value) => @utf8.encode(value)
  }
  match
    insert_bootstrap_journal_value(
      database, "client_worker_provisioning_custody", "parent", parent, bootstrap,
    ) {
    Err(issue) => return Err(Physical(issue))
    Ok(_) => ()
  }
  insert_bootstrap_journal_value(
    database, "client_worker_provisioning_custody", "selected", b"unissued", bootstrap,
  )
  .map(_ => ())
  .map_err(issue => Physical(issue))
}

///|
fn NativeLocalHostConnection::worker_provisioning_current(
  self : NativeLocalHostConnection,
  principal : String,
  connection : String,
  operation : String,
) -> Result[Unit, NativeLocalWorkerProvisioningIssue] {
  match self.check_binding() {
    Err(issue) => return Err(Adoption(issue))
    Ok(_) => ()
  }
  match
    self.authorize({ principal, connection, resource: "worker", operation, }) {
    Err(issue) => return Err(Adoption(issue))
    Ok(@authorization.Allow(_)) => ()
    Ok(_) => return Err(AuthorizationDenied)
  }
  let parent = match
    self.database.read("client_worker_provisioning_custody", "parent") {
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Adoption(Physical(issue)))
    Ok(value) => value
  }
  if parent.revision != 0L || parent.body != @utf8.encode(self.adoption_cid) {
    return Err(CustodyLost)
  }
  Ok(())
}

///|
fn NativeLocalHostConnection::worker_provisioning_body(
  self : NativeLocalHostConnection,
  original : @arena.InstalledArenaWorkerSelection,
  key : String,
) -> Result[Bytes, NativeLocalWorkerProvisioningIssue] {
  let (source, recipe, generation) = match
    @arena.installed_worker_selection_data(original) {
    Err(issue) => return Err(Selection(issue))
    Ok(value) => value
  }
  let (epoch_key, _, _) = match read_epoch_custody(self.database) {
    Err(issue) => return Err(Adoption(Epoch(issue)))
    Ok(value) => value
  }
  // Fingerprint only the existing epoch original. No signing key or new
  // credential purpose is issued, exposed or borrowed for this child operation.
  let epoch = match local_adoption_digest(self.epoch.crypto, epoch_key) {
    Err(issue) => return Err(Adoption(issue))
    Ok(value) => value
  }
  local_adoption_record([
    ("adoption", self.adoption_cid),
    ("epoch", epoch),
    ("key", key),
    ("source", source),
    ("recipe", epoch_hex(recipe)),
    ("generation", generation.to_string()),
    ("version", "actql-local-worker-provisioning/0.1"),
  ]).map_err(issue => NativeLocalWorkerProvisioningIssue::Adoption(issue))
}

///|
fn NativeLocalHostConnection::read_worker_provisioning_intent(
  self : NativeLocalHostConnection,
) -> Result[(String, Bytes), NativeLocalWorkerProvisioningIssue] {
  let (body, _) = match
    local_adoption_read(self.session.root, "worker-provisioning.json", 2048L) {
    Err(issue) => return Err(Adoption(issue))
    Ok(value) => value
  }
  let fields = match
    local_adoption_fields(body, [
      "adoption", "epoch", "key", "source", "recipe", "generation", "version",
    ]) {
    Err(_) => return Err(CustodyLost)
    Ok(value) => value
  }
  let (epoch_key, _, _) = match read_epoch_custody(self.database) {
    Err(issue) => return Err(Adoption(Epoch(issue)))
    Ok(value) => value
  }
  let epoch = match local_adoption_digest(self.epoch.crypto, epoch_key) {
    Err(issue) => return Err(Adoption(issue))
    Ok(value) => value
  }
  let generation = @string.parse_int64(fields[5]) catch {
    _ => return Err(CustodyLost)
  }
  if fields[0] != self.adoption_cid ||
    fields[1] != epoch ||
    fields[2].length() != 71 ||
    !fields[2].has_prefix("worker/") ||
    epoch_hex_bytes(fields[2].replace(old="worker/", new="")) is None ||
    fields[3].is_empty() ||
    fields[3].length() > 1024 ||
    epoch_hex_bytes(fields[4]) is None ||
    generation < 0L ||
    generation.to_string() != fields[5] ||
    fields[6] != "actql-local-worker-provisioning/0.1" {
    return Err(CustodyLost)
  }
  let expected = local_adoption_record([
    ("adoption", fields[0]),
    ("epoch", fields[1]),
    ("key", fields[2]),
    ("source", fields[3]),
    ("recipe", fields[4]),
    ("generation", fields[5]),
    ("version", fields[6]),
  ]).map_err(issue => NativeLocalWorkerProvisioningIssue::Adoption(issue))
  match expected {
    Ok(value) if value == body => Ok((fields[2], body))
    _ => Err(CustodyLost)
  }
}

///|
/// Lookup only: never generates a key, writes, acquires, reserves or launches.
/// Missing SQL after the durable intent is unresolved under the SAME key.
pub fn NativeLocalHostConnection::lookup_worker_provisioning(
  self : NativeLocalHostConnection,
  selection : @arena.InstalledArenaWorkerSelection,
  principal : String,
  connection : String,
) -> Result[
  NativeLocalWorkerProvisioningObservation,
  NativeLocalWorkerProvisioningIssue,
] {
  match self.worker_provisioning_current(principal, connection, "read") {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (key, body) = match self.read_worker_provisioning_intent() {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  match self.worker_provisioning_body(selection, key) {
    Ok(expected) if expected == body => ()
    Err(issue) => return Err(issue)
    Ok(_) => return Err(CustodyLost)
  }
  let observation = self.journal
    .transaction(() => {
      let selected = match
        self.database.read("client_worker_provisioning_custody", "selected") {
        Err(@sqlite.NotFound) => return Err(CustodyLost)
        Err(issue) => return Err(Physical(issue))
        Ok(value) => value
      }
      match self.database.read("client_worker_provisioning", key) {
        Err(@sqlite.NotFound) if selected.body == b"unissued" &&
          selected.revision == 0L => Ok(NotRecorded)
        Err(@sqlite.NotFound) => Err(CustodyLost)
        Err(issue) => Err(Physical(issue))
        Ok(value) if value.body == body &&
          value.revision == 0L &&
          selected.body == @utf8.encode(key) &&
          selected.revision == 1L => Ok(Recorded)
        Ok(_) => Err(CustodyLost)
      }
    })
    .map_err(issue => NativeLocalWorkerProvisioningIssue::Journal(issue))
  match observation {
    Err(issue) => return Err(issue)
    Ok(record) =>
      match self.worker_provisioning_current(principal, connection, "read") {
        Err(issue) => Err(issue)
        Ok(_) => Ok(UnresolvedOriginal(key, body, record))
      }
  }
}

///|
/// First issuance only, before the worker child acquires its physical resources.
/// Reopen is the separate read-only API above. Durable intent precedes SQL so a
/// failed/lost first SQL reply cannot turn the unissued row into a fresh key.
/// Later generations deliberately have NO issuer until actual predecessor
/// retirement is supplied by the existing Owner; missing rows are not proof.
pub fn NativeLocalHostConnection::issue_worker_provisioning(
  self : NativeLocalHostConnection,
  selection : @arena.InstalledArenaWorkerSelection,
  principal : String,
  connection : String,
) -> Result[
  NativeLocalWorkerProvisioningAttempt,
  NativeLocalWorkerProvisioningIssue,
] {
  match self.worker_provisioning_current(principal, connection, "provision") {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.worker_provisioning_attempt is Some(_) {
    return Err(CustodyLost)
  }
  for name in ["worker-provisioning.json", "worker-provisioning.json.stage"] {
    match self.session.root.inspect_generation(name) {
      Ok(None) => ()
      Ok(Some(_)) => return Err(CustodyLost)
      Err(issue) => return Err(Adoption(Filesystem(issue)))
    }
  }
  // Check the original durable selection BEFORE generating another identity.
  // A missing intent with an issued/missing SQL witness is custody loss.
  let selected = match
    self.database.read("client_worker_provisioning_custody", "selected") {
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Adoption(Physical(issue)))
    Ok(value) => value
  }
  if selected.body != b"unissued" || selected.revision != 0L {
    return Err(CustodyLost)
  }
  match self.database.scan_after("client_worker_provisioning", "") {
    Err(@sqlite.NotFound) => ()
    Err(issue) => return Err(Adoption(Physical(issue)))
    Ok(_) => return Err(CustodyLost)
  }
  let nonce = match self.epoch.crypto.random_bytes(32) {
    Err(issue) => return Err(Adoption(Crypto(issue)))
    Ok(value) => value
  }
  let key = "worker/" + epoch_hex(nonce)
  let body = match self.worker_provisioning_body(selection, key) {
    Err(issue) => return Err(issue)
    Ok(value) if value.length() <= 2048 => value
    Ok(_) => return Err(CustodyLost)
  }
  let original : NativeLocalWorkerProvisioningAttempt = {
    host: self,
    selection,
    body,
    key,
    resource: None,
  }
  // Same Host retains every partial original BEFORE file/SQL I/O. Nothing in
  // this record permits physical acquisition or supplies a worker continuation.
  self.worker_provisioning_attempt = Some(original)
  match
    local_adoption_write(self.session.root, "worker-provisioning.json", body) {
    Err(issue) => return Err(Adoption(issue))
    Ok(_) => ()
  }
  let written = self.journal.transaction(() => {
    let selected = match
      self.database.read("client_worker_provisioning_custody", "selected") {
      Err(@sqlite.NotFound) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
      Ok(value) => value
    }
    if selected.body != b"unissued" || selected.revision != 0L {
      return Err(CustodyLost)
    }
    match self.database.scan_after("client_worker_provisioning", "") {
      Err(@sqlite.NotFound) => ()
      Err(issue) => return Err(Physical(issue))
      Ok(_) => return Err(CustodyLost)
    }
    // Existing bounded settings budget, not another resource/funding Ledger.
    // At most three 2048-byte copies (intent, immutable SQL, live carrier).
    match
      self.database.reserve_capacity_in_transaction(
        "client_local_settings", "worker-provisioning", 8192L, 1L, 65536L, 8L,
      ) {
      Err(issue) => return Err(Physical(issue))
      Ok(true) => ()
      Ok(false) => return Err(CustodyLost)
    }
    match self.database.insert("client_worker_provisioning", key, body) {
      Err(issue) => return Err(Physical(issue))
      Ok(_) => ()
    }
    match
      self.database.compare_exchange(
        "client_worker_provisioning_custody",
        "selected",
        0L,
        @utf8.encode(key),
      ) {
      Err(issue) => return Err(Physical(issue))
      Ok(_) => ()
    }
    match self.worker_provisioning_current(principal, connection, "provision") {
      Err(issue) => Err(worker_provisioning_journal_issue(issue))
      Ok(_) => Ok(())
    }
  })
  match written {
    Err(issue) => Err(Journal(issue))
    Ok(_) =>
      match
        self.worker_provisioning_current(principal, connection, "provision") {
        Err(issue) => Err(issue)
        Ok(_) => Ok(original)
      }
  }
}

///|
/// The partial carrier keeps the same original key and selection. This only
/// observes the saved journal; it cannot retry a write or physical operation.
pub fn NativeLocalWorkerProvisioningAttempt::observe(
  self : NativeLocalWorkerProvisioningAttempt,
  principal : String,
  connection : String,
) -> Result[
  NativeLocalWorkerProvisioningObservation,
  NativeLocalWorkerProvisioningIssue,
] {
  if !(self.host.worker_provisioning_attempt is Some(original) &&
    physical_equal(original, self)) {
    return Err(CustodyLost)
  }
  match
    self.host.lookup_worker_provisioning(self.selection, principal, connection) {
    Ok(UnresolvedOriginal(key, body, state)) if key == self.key &&
      body == self.body => Ok(UnresolvedOriginal(key, body, state))
    Ok(_) => Err(CustodyLost)
    Err(issue) => Err(issue)
  }
}

///|
// Preserve actual physical/epoch/fence failures across the existing journal's
// typed error boundary. A current-observation failure is not author denial.
fn worker_provisioning_journal_issue(
  issue : NativeLocalWorkerProvisioningIssue,
) -> NativeClientRunJournalIssue {
  match issue {
    Adoption(Physical(physical)) => Physical(physical)
    Adoption(Epoch(epoch)) => Epoch(epoch)
    Adoption(Fenced) => Fenced
    Adoption(TransactionUnknown) => TransactionUnknown
    Adoption(Journal(journal)) | Journal(journal) => journal
    AuthorizationDenied => AuthorizationDenied
    _ => CustodyLost
  }
}
