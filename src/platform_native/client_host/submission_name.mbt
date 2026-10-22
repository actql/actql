///|
/// A committed name is occupied even when its original intent was retired.
/// These observations do not authorize preparation, execution or a retry.
pub enum NativeClientNamedSubmissionLookup {
  UnresolvedName
  UnresolvedNamedSubmissionHistory
  NamedSubmission(Bool, NativeClientSubmittedIntentRecord)
}

///|
fn named_submission_index(
  key : @host.ClientSubmittedNameKey,
) -> Result[String, NativeClientRunJournalIssue] {
  // Generic SQLite journal keys are at most 512 bytes. Hash only the three
  // original index coordinates, then compare all retained coordinates too.
  // This is a private physical locator, not a new CID or release authority.
  @host.client_submitted_name_index_input(key)
  .map(input => @sha.hex(@utf8.encode(input)))
  .map_err(issue => NamedSubmission(issue))
}

///|
// Fresh installer initialization only. Absence on restore is never repaired.
fn initialize_native_client_submitted_names(
  database : @sqlite.Database,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if client_journal_transaction_fenced(
      database,
      bootstrap_journal_reads(bootstrap),
    ) {
    return Err(Fenced)
  }
  for
    namespace_id in [
      "client_submission_name_custody", "client_submission_names",
    ] {
    match
      scan_client_journal_value(
        database,
        namespace_id,
        "",
        bootstrap_journal_reads(bootstrap),
      ) {
      Err(@sqlite.NotFound) => ()
      Ok(_) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
  }
  match
    insert_bootstrap_journal_value(
      database, "client_submission_name_custody", "issued", b"0", bootstrap,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  match
    insert_bootstrap_journal_value(
      database, "client_submission_name_custody", "retained", b"0", bootstrap,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  if !install_bootstrap_submission_name_schema(database, bootstrap) {
    return Err(CustodyLost)
  }
  Ok(())
}

///|
fn NativeClientRunJournal::authenticated_name_row(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  index : String,
  body : Bytes,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[@host.ClientSubmittedNameRow, NativeClientRunJournalIssue] {
  let row = match @host.decode_client_submitted_name_row(body) {
    Ok(value) => value
    Err(issue) => return Err(NamedSubmission(issue))
  }
  let (key, _, _, _) = @host.client_submitted_name_binding_fields(row.binding)
  let expected_index = match named_submission_index(key) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if expected_index != index {
    return Err(CustodyLost)
  }
  let (secret, _, _) = match read_epoch_custody(self.database, reads~) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(issue))
  }
  let original = match
    @host.client_submitted_name_authentication_input(row.binding, 8192) {
    Ok(value) => value
    Err(issue) => return Err(NamedSubmission(issue))
  }
  match
    authority.crypto.verify_hmac_sha256(
      secret,
      @utf8.encode(original),
      row.authenticator,
    ) {
    Ok(true) => Ok(row)
    Ok(false) => Err(CustodyLost)
    Err(issue) => Err(Epoch(Crypto(issue)))
  }
}

///|
fn NativeClientRunJournal::submitted_name_custody(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
) -> Result[(Int, Int64), NativeClientRunJournalIssue] {
  if !physical_equal(self.database, authority.database) {
    return Err(InvalidSubmission)
  }
  self.submitted_name_control()
}

///|
fn native_client_submitted_name_index(
  namespace_id : String,
  actor : String,
  name : String,
  authority_scope_cid : String,
) -> Result[(@host.ClientSubmittedNameKey, String), NativeClientRunJournalIssue] {
  let key = match
    @host.prepare_client_submitted_name_key(
      namespace_id, actor, name, authority_scope_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NamedSubmission(issue))
  }
  let index = match named_submission_index(key) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok((key, index))
}

///|
/// Resolve before considering a candidate reference. A retained name always
/// authenticates its original epoch for lookup; it never renews it or repeats
/// preparation. None is lookup-only, not permission to choose a fresh nonce.
/// The trusted Host caller retains current callbacks and terminal fences.
pub fn NativeClientRunJournal::resolve_or_bind_submitted_name(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  namespace_id : String,
  actor : String,
  name : String,
  intent : @host.ClientSubmittedIntent,
  candidate : NativeClientSubmissionReference?,
  authority_scope_cid : String,
  current_authorization : Bool,
  now : Double,
) -> Result[NativeClientNamedSubmissionLookup, NativeClientRunJournalIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  if !physical_equal(self.database, authority.database) {
    return Err(InvalidSubmission)
  }
  let (key, index) = match
    native_client_submitted_name_index(
      namespace_id, actor, name, authority_scope_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Exactly the original monotonic epoch clock: its COMMIT is independent of
  // the following append transaction, including when that transaction refuses.
  match authority.clock(now) {
    Ok(_) => ()
    Err(issue) => return Err(Epoch(issue))
  }
  self.transaction(() => {
    self.resolve_submitted_name_locked(
      authority, key, index, intent, candidate, authority_scope_cid, current_authorization,
    )
  })
}

///|
// Same original transaction body. The public legacy adapter and the trusted
// Host entry share this work; neither changes the inherited custody validator.
fn NativeClientRunJournal::resolve_submitted_name_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  key : @host.ClientSubmittedNameKey,
  index : String,
  intent : @host.ClientSubmittedIntent,
  candidate : NativeClientSubmissionReference?,
  authority_scope_cid : String,
  current_authorization : Bool,
) -> Result[NativeClientNamedSubmissionLookup, NativeClientRunJournalIssue] {
  let (count, revision) = match self.submitted_name_custody(authority) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    client_journal_issuance_anchor(
      self.database,
      "client_submitted_intent_custody",
      self.max_records,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let retained = match self.database.read("client_submission_names", index) {
    Ok(row) => Some(row)
    Err(@sqlite.NotFound) => None
    Err(issue) => return Err(Physical(issue))
  }
  if retained is Some(retained) {
    let row = match
      self.authenticated_name_row(authority, index, retained.body) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let (original_key, scope, submission_id, expected_intent) = @host.client_submitted_name_binding_fields(
      row.binding,
    )
    if original_key != key {
      return Err(CustodyLost)
    }
    // Preserve conflict priority even when the original intent was retired.
    if scope != authority_scope_cid ||
      expected_intent != @host.client_submitted_intent_cid(intent) {
      return Err(ChangedIntent)
    }
    let saved = match
      self.database.read("client_submitted_intents", submission_id) {
      Ok(row) =>
        match @host.decode_client_submitted_journal_row(row.body) {
          Ok(value) => value
          Err(_) => return Err(CustodyLost)
        }
      Err(@sqlite.NotFound) => return Ok(UnresolvedNamedSubmissionHistory)
      Err(issue) => return Err(Physical(issue))
    }
    let original = match
      @host.inspect_client_named_submitted_original(
        key,
        authority_scope_cid,
        intent,
        row.binding,
        Some(saved.reference),
        Some(saved.intent),
      ) {
      Ok(value) => native_submission_reference_record(value)
      Err(@host.ChangedIntent) => return Err(ChangedIntent)
      Err(issue) => return Err(NamedSubmission(issue))
    }
    match
      self.verify_submission_locked(
        authority, original, authority_scope_cid, current_authorization,
      ) {
      Ok(_) => () // Expired is an authenticated historical lookup only.
      Err(issue) => return Err(issue)
    }
    return self
      .retained_submission(original)
      .map(record => {
        match record {
          Some(record) => NamedSubmission(false, record)
          None => UnresolvedNamedSubmissionHistory
        }
      })
  }
  guard candidate is Some(candidate) else { return Ok(UnresolvedName) }
  if count >= self.max_records {
    return Err(CapacityExceeded)
  }
  match
    self.verify_submission_locked(
      authority, candidate, authority_scope_cid, current_authorization,
    ) {
    Ok(@scope.Admissible) => ()
    Ok(value) => return Err(SubmissionEpochRejected(value))
    Err(issue) => return Err(issue)
  }
  // Naming an already used nonce would retroactively change its identity.
  match self.database.read("client_submitted_intents", candidate.request_id) {
    Ok(_) => return Err(SubmissionReferenceUsed)
    Err(@sqlite.NotFound) => ()
    Err(issue) => return Err(Physical(issue))
  }
  let binding = match
    @host.prepare_client_submitted_name_binding(
      key,
      authority_scope_cid,
      candidate.request_id,
      @host.client_submitted_intent_cid(intent),
    ) {
    Ok(value) => value
    Err(issue) => return Err(NamedSubmission(issue))
  }
  let original = match
    @host.client_submitted_name_authentication_input(binding, 8192) {
    Ok(value) => value
    Err(issue) => return Err(NamedSubmission(issue))
  }
  let (secret, _, _) = match read_epoch_custody(self.database) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(issue))
  }
  let authenticator = match
    authority.crypto.hmac_sha256(secret, @utf8.encode(original)) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(Crypto(issue)))
  }
  let body = match
    @host.client_submitted_name_row_body({ binding, authenticator, }) {
    Ok(value) => value
    Err(issue) => return Err(NamedSubmission(issue))
  }
  let record = match
    self.record_submitted_intent_locked(
      authority, candidate, intent, authority_scope_cid, current_authorization,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.database.insert("client_submission_names", index, body) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  match
    self.database.compare_exchange(
      "client_submission_name_custody",
      "issued",
      revision,
      @utf8.encode((count + 1).to_string()),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  match self.submitted_name_custody(authority) {
    Ok(_) => Ok(NamedSubmission(true, record))
    Err(issue) => Err(issue)
  }
}
