///|
/// An original public SubmissionReference, not read authority or acceptance.
struct NativeClientSubmissionReference {
  epoch : NativeClientSubmissionEpoch
  request_id : String
  wire : String
}

///|
pub fn native_client_submission_reference_wire(
  value : NativeClientSubmissionReference,
) -> String {
  value.wire
}

///|
pub fn native_client_submission_request_id(
  value : NativeClientSubmissionReference,
) -> String {
  value.request_id
}

///|
fn native_submission_reference_record(
  value : @host.ClientSubmissionReferenceRecord,
) -> NativeClientSubmissionReference {
  let epoch = @host.client_submission_reference_record_epoch(value)
  {
    epoch: {
      body: @host.client_submission_epoch_token_body(epoch),
      tag: @host.client_submission_epoch_token_tag(epoch),
      wire: @host.client_submission_epoch_token_wire(epoch),
    },
    request_id: @host.client_submission_reference_record_request_id(value),
    wire: @host.client_submission_reference_record_wire(value),
  }
}

///|
fn native_submission_reference_issue(
  issue : @host.ClientSubmissionReferenceRecordIssue,
) -> NativeClientRunJournalIssue {
  match issue {
    @host.InvalidReference => InvalidSubmission
    @host.Encoding => Encoding
    @host.Epoch(@host.Unverifiable) => Epoch(Unverifiable)
    @host.Epoch(@host.Identity(issue)) => Epoch(Identity(issue))
  }
}

///|
pub fn prepare_native_client_submission_reference(
  epoch : NativeClientSubmissionEpoch,
  nonce : String,
) -> Result[NativeClientSubmissionReference, NativeClientRunJournalIssue] {
  // Preserve the original typed nonce rejection before token serialization.
  if @scope.submission_request_id(epoch.body, nonce) is Err(_) {
    return Err(InvalidSubmission)
  }
  let token = match @host.admit_client_submission_epoch_token(epoch.wire) {
    Ok(value) => value
    Err(@host.Unverifiable) => return Err(Epoch(Unverifiable))
    Err(@host.Identity(issue)) => return Err(Epoch(Identity(issue)))
  }
  @host.prepare_client_submission_reference_record(token, nonce)
  .map(native_submission_reference_record)
  .map_err(native_submission_reference_issue)
}

///|
pub fn admit_native_client_submission_reference(
  wire : String,
) -> Result[NativeClientSubmissionReference, NativeClientRunJournalIssue] {
  @host.admit_client_submission_reference_record(wire)
  .map(native_submission_reference_record)
  .map_err(native_submission_reference_issue)
}

///|
/// Existing request-journal custody before a Run is issued. The original
/// submitted intent is admitted by the shared owner, never reconstructed from
/// a prepared Program. A retained Run admission is separate from dispatch,
/// execution outcome, retry permission and a public refusal.
struct NativeClientSubmittedIntentRecord {
  reference : NativeClientSubmissionReference
  intent : @host.ClientSubmittedIntent
  run_admission : NativeClientSubmittedRunAdmission?
  revision : Int64
}

///|
pub enum NativeClientSubmittedIntentLookup {
  UnresolvedSubmissionHistory
  Submitted(NativeClientSubmittedIntentRecord)
}

///|
pub fn native_client_submitted_intent(
  value : NativeClientSubmittedIntentRecord,
) -> @host.ClientSubmittedIntent {
  value.intent
}

///|
pub fn native_client_submitted_intent_revision(
  value : NativeClientSubmittedIntentRecord,
) -> Int64 {
  value.revision
}

///|
fn submitted_intent_body(
  reference : NativeClientSubmissionReference,
  intent : @host.ClientSubmittedIntent,
  run_admission? : NativeClientSubmittedRunAdmission? = None,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  @host.client_submitted_intent_journal_row_body(
    reference.wire,
    intent,
    run_admission=run_admission.map(admission => {
      (admission.request, admission.run_definition_cid, admission.revision)
    }),
  ).map_err(issue => {
    match issue {
      Encoding => Encoding
      CapacityExceeded => CapacityExceeded
    }
  })
}

///|
fn read_submitted_intent(
  row : @sqlite.NativeJournalValue,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  let decoded = match @host.decode_client_submitted_journal_row(row.body) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  Ok({
    reference: native_submission_reference_record(decoded.reference),
    intent: decoded.intent,
    run_admission: decoded.run_admission.map(value => {
      request: value.0,
      run_definition_cid: value.1,
      revision: value.2,
    }),
    revision: row.revision,
  })
}

///|
/// Only trusted fresh-format initialization may create this independent
/// issuance record. It is not an automatic repair of missing intent custody.
fn initialize_native_client_submitted_intents(
  database : @sqlite.Database,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if database.transaction_fenced() {
    return Err(Fenced)
  }
  match database.scan_after("client_submitted_intent_custody", "") {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  match database.scan_after("client_submitted_intents", "") {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  database
  .insert("client_submitted_intent_custody", "issued", b"0")
  .map(_ => ())
  .map_err(issue => Physical(issue))
}

///|
fn NativeClientRunJournal::submitted_intent_custody(
  self : NativeClientRunJournal,
) -> Result[(Int, Int64, Int64), NativeClientRunJournalIssue] {
  match self.database.scan_after("client_submitted_intent_custody", "") {
    Ok(row) if row.key == "issued" => ()
    _ => return Err(CustodyLost)
  }
  match self.database.scan_after("client_submitted_intent_custody", "issued") {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  let custody = match
    self.database.read("client_submitted_intent_custody", "issued") {
    Ok(value) => value
    _ => return Err(CustodyLost)
  }
  let count = match
    @host.client_journal_issuance_count(custody.body, self.max_records) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let mut cursor = ""
  let mut observed = 0
  let mut retained_bytes = 0L
  while true {
    let row = match
      self.database.scan_after("client_submitted_intents", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    observed = observed + 1
    if observed > count {
      return Err(CustodyLost)
    }
    let record = match
      read_submitted_intent({ body: row.body, revision: row.revision, }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if record.reference.request_id != row.key {
      return Err(CustodyLost)
    }
    match self.validate_submitted_run_admission(record) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    retained_bytes = retained_bytes +
      @utf8.encode(@host.client_submitted_intent_wire(record.intent))
      .length()
      .to_int64()
    if retained_bytes > 67108864L {
      return Err(CustodyLost)
    }
    cursor = row.key
  }
  if observed != count {
    return Err(CustodyLost)
  }
  Ok((count, retained_bytes, custody.revision))
}

///|
fn NativeClientRunJournal::verify_submission_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  authority_scope_cid : String,
  current_authorization : Bool,
) -> Result[@scope.SubmissionEpochValidity, NativeClientRunJournalIssue] {
  if !physical_equal(self.database, authority.database) {
    return Err(InvalidSubmission)
  }
  authority
  .verify_epoch_locked(
    reference.epoch,
    authority_scope_cid,
    current_authorization,
  )
  .map_err(issue => Epoch(issue))
}

///|
fn NativeClientRunJournal::retained_submission(
  self : NativeClientRunJournal,
  reference : NativeClientSubmissionReference,
) -> Result[NativeClientSubmittedIntentRecord?, NativeClientRunJournalIssue] {
  let row = match
    self.database.read("client_submitted_intents", reference.request_id) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok(None)
    Err(issue) => return Err(Physical(issue))
  }
  let record = match read_submitted_intent(row) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if record.reference.wire != reference.wire {
    return Err(CustodyLost)
  }
  match self.validate_submitted_run_admission(record) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(Some(record))
}

///|
/// Preserve one exact unchecked intent in the existing request journal. The
/// returned record acknowledges preparing only; it cannot authorize work.
/// Count and row commit together. A lost commit reply fences the same handle.
pub fn NativeClientRunJournal::record_submitted_intent(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  intent : @host.ClientSubmittedIntent,
  authority_scope_cid : String,
  current_authorization : Bool,
  now : Double,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  if !physical_equal(self.database, authority.database) {
    return Err(InvalidSubmission)
  }
  match
    authority.verify_epoch(
      reference.epoch,
      authority_scope_cid,
      current_authorization,
      now,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Epoch(issue))
  }
  self.transaction(() => {
    let validity = match
      self.verify_submission_locked(
        authority, reference, authority_scope_cid, current_authorization,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let (count, retained_bytes, revision) = match
      self.submitted_intent_custody() {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match self.retained_submission(reference) {
      Ok(Some(record)) => {
        if @host.client_submitted_intent_cid(record.intent) !=
          @host.client_submitted_intent_cid(intent) {
          return Err(ChangedIntent)
        }
        return Ok(record)
      }
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
    if validity != @scope.Admissible {
      return Err(SubmissionEpochRejected(validity))
    }
    let bytes = @utf8.encode(@host.client_submitted_intent_wire(intent))
      .length()
      .to_int64()
    if count == self.max_records || bytes > 67108864L - retained_bytes {
      return Err(CapacityExceeded)
    }
    let body = match submitted_intent_body(reference, intent) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match
      self.database.compare_exchange(
        "client_submitted_intent_custody",
        "issued",
        revision,
        @utf8.encode((count + 1).to_string()),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
    self.database
    .insert("client_submitted_intents", reference.request_id, body)
    .map(revision => { reference, intent, run_admission: None, revision, })
    .map_err(issue => Physical(issue))
  })
}

///|
/// Lookup authenticates the original epoch even after expiry, with current
/// scope authority. Missing history never means nonexecution or a new start.
/// It does not prepare a Program, bind a Run, reserve work or dispatch.
pub fn NativeClientRunJournal::lookup_submitted_intent(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  authority_scope_cid : String,
  current_authorization : Bool,
  now : Double,
) -> Result[NativeClientSubmittedIntentLookup, NativeClientRunJournalIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  if !physical_equal(self.database, authority.database) {
    return Err(InvalidSubmission)
  }
  match
    authority.verify_epoch(
      reference.epoch,
      authority_scope_cid,
      current_authorization,
      now,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Epoch(issue))
  }
  self.transaction(() => {
    match
      self.verify_submission_locked(
        authority, reference, authority_scope_cid, current_authorization,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match self.submitted_intent_custody() {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    self
    .retained_submission(reference)
    .map(record => {
      match record {
        Some(value) => Submitted(value)
        None => UnresolvedSubmissionHistory
      }
    })
  })
}
