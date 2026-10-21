///|
// A subordinate locator in the existing Journal, never Run authority. The
// referenced original is authenticated again before a selection escapes.
fn run_id_index_key(scope : String, id : String) -> String {
  @sha.hex(@utf8.encode(scope + "\u{0000}" + id))
}

///|
fn NativeClientRunJournal::index_run_id_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  run : NativeClientRunRecord,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.transaction_active ||
    !physical_equal(self.database, authority.database) {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  let scope = @host.client_request_authority_scope_cid(run.request)
  let id = match @publication.run_definition_run_id(run.definition) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let key = run_id_index_key(scope, id)
  let body = @utf8.encode(reference.wire)
  match
    read_client_journal_value(self.database, "client_run_id_index", key, reads) {
    Err(@sqlite.NotFound) =>
      insert_client_journal_value(
        self.database,
        "client_run_id_index",
        key,
        body,
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    Err(issue) => Err(Physical(issue))
    Ok(original) => {
      if original.body == b"ambiguous" {
        return Ok(())
      }
      let original_reference = match
        read_run_id_index_reference(original.body) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        self.run_id_original_locked(
          authority,
          original_reference,
          scope,
          id,
          reads~,
        ) {
        Ok(Some(_)) => ()
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      if original.body == body {
        return Ok(())
      }
      // Preserve the former ambiguous-ID refusal without forbidding a second
      // otherwise valid admission. No ordinary lookup chooses the first row.
      compare_exchange_client_journal_value(
        self.database,
        "client_run_id_index",
        key,
        original.revision,
        b"ambiguous",
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    }
  }
}

///|
fn read_run_id_index_reference(
  body : Bytes,
) -> Result[NativeClientSubmissionReference, NativeClientRunJournalIssue] {
  let wire = @utf8.decode(body) catch { _ => return Err(CustodyLost) }
  @host.admit_client_submission_reference_record(wire)
  .map(native_submission_reference_record)
  .map_err(_ => CustodyLost)
}

///|
fn NativeClientRunJournal::run_id_original_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  scope : String,
  id : String,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[
  (
    NativeClientSubmissionReference,
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
  )?,
  NativeClientRunJournalIssue,
] {
  match
    self.verify_submission_locked(authority, reference, scope, true, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (submission, selected) = match
    self.retained_submission_with_run(reference, reads~) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  guard submission.run_admission is Some(admission) && selected is Some(run) else {
    return Ok(None)
  }
  if @host.client_request_authority_scope_cid(admission.request) != scope ||
    !(@publication.run_definition_run_id(run.definition) is Ok(original_id) &&
    original_id == id) {
    return Ok(None)
  }
  Ok(Some((reference, run.request, run.definition)))
}

///|
// Explicit bounded compatibility indexing, outside ordinary open/read. It
// authenticates existing originals; it never creates a Submission/Run, repairs
// missing custody, renews an epoch or permits a resend. The caller owns current
// authorization and the original Journal transaction/COMMIT Unknown handling.
fn NativeClientRunJournal::index_legacy_run_ids_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  scope : String,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.transaction_active {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  let mut cursor = ""
  let mut count = 0
  while true {
    let row = match
      scan_client_journal_value(
        self.database,
        "client_submitted_intents",
        cursor,
        reads,
      ) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    count += 1
    if count > self.max_records || row.key <= cursor {
      return Err(CustodyLost)
    }
    cursor = row.key
    let decoded = match
      self.inspect_submitted_intent_row(
        { key: row.key, body: row.body, revision: row.revision, },
        reads~,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard decoded.run_admission is Some((request, _, _)) else { continue }
    if @host.client_request_authority_scope_cid(request) != scope {
      continue
    }
    let reference = native_submission_reference_record(decoded.reference)
    match
      self.verify_submission_locked(authority, reference, scope, true, reads~) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let run = match self.retained(request, reads~) {
      Ok(Some(value)) => value
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    match self.index_run_id_locked(authority, reference, run, operations~) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match
      self.index_saved_run_reference_locked(
        authority,
        reference,
        run,
        operations~,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  // Completeness belongs to this exact issuance snapshot. Later admissions
  // change its anchor, so a missing locator cannot become false absence.
  let issuance = match
    client_journal_issuance_anchor(
      self.database,
      "client_submitted_intent_custody",
      self.max_records,
      reads~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if count != issuance.0 {
    return Err(CustodyLost)
  }
  let body = @utf8.encode(issuance.0.to_string() + ":" + issuance.1.to_string())
  match
    read_client_journal_value(
      self.database,
      "client_run_id_index_coverage",
      scope,
      reads,
    ) {
    Err(@sqlite.NotFound) =>
      insert_client_journal_value(
        self.database,
        "client_run_id_index_coverage",
        scope,
        body,
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    Err(issue) => Err(Physical(issue))
    Ok(original) =>
      compare_exchange_client_journal_value(
        self.database,
        "client_run_id_index_coverage",
        scope,
        original.revision,
        body,
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
  }
}

///|
// Missing coverage is not evidence that an arbitrary historical Run is absent.
fn NativeClientRunJournal::run_id_absence_locked(
  self : NativeClientRunJournal,
  scope : String,
  issuance : (Int, Int64),
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[
  (
    NativeClientSubmissionReference,
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
  )?,
  NativeClientRunJournalIssue,
] {
  if issuance.0 == 0 {
    return Ok(None)
  }
  let expected = @utf8.encode(
    issuance.0.to_string() + ":" + issuance.1.to_string(),
  )
  match
    read_client_journal_value(
      self.database,
      "client_run_id_index_coverage",
      scope,
      reads,
    ) {
    Ok(original) if original.body == expected => Ok(None)
    Ok(_) | Err(@sqlite.NotFound) => Err(RunIdIndexIncomplete)
    Err(issue) => Err(Physical(issue))
  }
}

///|
/// Explicit bounded compatibility indexing on this adopted Host. This does
/// not run during ordinary open/lookup, initialize history, issue an epoch or
/// permit execution. The same current RunRead and transaction must survive
/// the entire indexing operation; COMMIT uncertainty retains its usual fence.
pub fn NativeLocalHostConnection::index_saved_run_ids(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
) -> Result[Unit, NativeClientSavedRunStateIssue] {
  let scope = match self.authority_scope_cid(principal, connection, crypto) {
    Ok(value) => value
    Err(_) => return Err(Journal(AuthorizationDenied))
  }
  let current = () => {
    saved_run_selection_current(self, crypto, principal, connection, scope)
  }
  if !current() {
    return Err(Journal(AuthorizationDenied))
  }
  let indexed = self.journal.transaction(() => {
    if !current() {
      return Err(AuthorizationDenied)
    }
    match self.journal.index_legacy_run_ids_locked(self.epoch, scope) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    if !current() {
      return Err(AuthorizationDenied)
    }
    Ok(())
  })
  match indexed {
    Err(issue) => Err(Journal(issue))
    Ok(_) if !current() => Err(Journal(AuthorizationDenied))
    Ok(_) => Ok(())
  }
}

///|
fn NativeClientRunJournal::index_saved_run_reference_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  run : NativeClientRunRecord,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.transaction_active ||
    !physical_equal(self.database, authority.database) {
    return Err(CustodyLost)
  }
  let original = match
    @host.admit_client_submission_reference_record(reference.wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let (key, body) = match
    @host.client_saved_run_reference_locator(
      original,
      run.request,
      run.definition,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  match
    read_client_journal_value(
      self.database,
      "client_run_reference_index",
      key,
      reads,
    ) {
    Err(@sqlite.NotFound) =>
      insert_client_journal_value(
        self.database,
        "client_run_reference_index",
        key,
        body,
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    Err(issue) => Err(Physical(issue))
    Ok(existing) => {
      if existing.body == body || existing.body == b"ambiguous" {
        return Ok(())
      }
      let earlier = match read_run_id_index_reference(existing.body) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let id = match @publication.run_definition_run_id(run.definition) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let (old_reference, old_request, old_definition) = match
        self.run_id_original_locked(
          authority,
          earlier,
          @host.client_request_authority_scope_cid(run.request),
          id,
          reads~,
        ) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      let old_original = match
        @host.admit_client_submission_reference_record(old_reference.wire) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      match
        @host.client_saved_run_reference_locator(
          old_original, old_request, old_definition,
        ) {
        Ok((old_key, old_body)) if old_key == key && old_body == existing.body =>
          ()
        _ => return Err(CustodyLost)
      }
      compare_exchange_client_journal_value(
        self.database,
        "client_run_reference_index",
        key,
        existing.revision,
        b"ambiguous",
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    }
  }
}
