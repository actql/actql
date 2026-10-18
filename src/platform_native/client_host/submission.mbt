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
  run_state_original : String?
  run_state_observation : (Int64, String?)?
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
  run_state_original? : String? = None,
  run_state_observation? : (Int64, String?)? = None,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  @host.client_submitted_intent_journal_row_body(
    reference.wire,
    intent,
    run_state_original~,
    run_state_observation~,
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
/// Only trusted fresh-format initialization may create this independent
/// issuance record. It is not an automatic repair of missing intent custody.
fn initialize_native_client_submitted_intents(
  database : @sqlite.Database,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if client_journal_transaction_fenced(
      database,
      bootstrap_journal_reads(bootstrap),
    ) {
    return Err(Fenced)
  }
  match
    scan_client_journal_value(
      database,
      "client_submitted_intent_custody",
      "",
      bootstrap_journal_reads(bootstrap),
    ) {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  match
    scan_client_journal_value(
      database,
      "client_submitted_intents",
      "",
      bootstrap_journal_reads(bootstrap),
    ) {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  insert_bootstrap_journal_value(
    database, "client_submitted_intent_custody", "issued", b"0", bootstrap,
  )
  .map(_ => ())
  .map_err(issue => Physical(issue))
}

///|
fn NativeClientRunJournal::submitted_intent_custody(
  self : NativeClientRunJournal,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[(Int, Int64, Int64), NativeClientRunJournalIssue] {
  @host.inspect_client_submitted_journal_inventory(
    self.max_records,
    (table_name, cursor) => {
      client_journal_scan(self.database, table_name, cursor, reads~)
    },
    (table_name, key) => {
      client_journal_read(self.database, table_name, key, reads~)
    },
    row => self.inspect_submitted_intent_row(row, reads~),
    CustodyLost,
  )
}

///|
fn NativeClientRunJournal::inspect_submitted_intent_row(
  self : NativeClientRunJournal,
  row : @host.ClientJournalPhysicalRow,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[@host.ClientSubmittedJournalEncoding, NativeClientRunJournalIssue] {
  let original = match @host.decode_client_submitted_journal_row(row.body) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let record : NativeClientSubmittedIntentRecord = {
    reference: native_submission_reference_record(original.reference),
    intent: original.intent,
    run_admission: original.run_admission.map(value => {
      request: value.0,
      run_definition_cid: value.1,
      revision: value.2,
    }),
    revision: row.revision,
    run_state_original: original.run_state_original,
    run_state_observation: original.run_state_observation,
  }
  if record.reference.request_id != row.key {
    return Err(CustodyLost)
  }
  match self.validate_submitted_run_admission(record, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok(original)
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
  let original_reference = match
    @host.admit_client_submission_reference_record(reference.wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  @host.read_client_saved_submission(
    original_reference,
    (table_name, key) => client_journal_read(self.database, table_name, key),
    row => {
      let record = match
        read_run_record({ body: row.body, revision: row.revision, }) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      Ok({
        request: record.request,
        definition: record.definition,
        checkpoint: record.checkpoint.map(value => value.effect_ledger),
      })
    },
    CustodyLost,
  ).map(value => {
    value.map(snapshot => {
      let decoded = @host.client_saved_submission_record(snapshot)
      {
        reference: native_submission_reference_record(decoded.reference),
        intent: decoded.intent,
        run_admission: decoded.run_admission.map(value => {
          request: value.0,
          run_definition_cid: value.1,
          revision: value.2,
        }),
        revision: @host.client_saved_submission_revision(snapshot),
        run_state_original: decoded.run_state_original,
        run_state_observation: decoded.run_state_observation,
      }
    })
  })
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
    self.record_submitted_intent_locked(
      authority, reference, intent, authority_scope_cid, current_authorization,
    )
  })
}

///|
// Same append plan and exact rows as the ordinary reference path. The caller
// already owns this journal transaction and has committed the epoch clock.
fn NativeClientRunJournal::record_submitted_intent_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  intent : @host.ClientSubmittedIntent,
  authority_scope_cid : String,
  current_authorization : Bool,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  let validity = match
    self.verify_submission_locked(
      authority, reference, authority_scope_cid, current_authorization,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original_reference = match
    @host.admit_client_submission_reference_record(reference.wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let plan = match
    @host.prepare_client_submitted_journal_append(
      original_reference,
      intent,
      validity,
      self.max_records,
      (table, cursor) => client_journal_scan(self.database, table, cursor),
      (table, key) => client_journal_read(self.database, table, key),
      row => self.inspect_submitted_intent_row(row),
      row => {
        let record = match
          read_run_record({ body: row.body, revision: row.revision, }) {
          Ok(value) => value
          Err(_) => return Err(CustodyLost)
        }
        Ok({
          request: record.request,
          definition: record.definition,
          checkpoint: record.checkpoint.map(value => value.effect_ledger),
        })
      },
      CustodyLost,
    ) {
    Ok(@host.Retained(snapshot)) => {
      let original = @host.client_saved_submission_record(snapshot)
      return Ok({
        reference: native_submission_reference_record(original.reference),
        intent: original.intent,
        run_admission: original.run_admission.map(value => {
          request: value.0,
          run_definition_cid: value.1,
          revision: value.2,
        }),
        revision: @host.client_saved_submission_revision(snapshot),
        run_state_original: original.run_state_original,
        run_state_observation: original.run_state_observation,
      })
    }
    Ok(@host.Append(plan)) => plan
    Err(@host.Observation(issue)) => return Err(issue)
    Err(@host.ChangedIntent) => return Err(ChangedIntent)
    Err(@host.EpochRejected(validity)) =>
      return Err(SubmissionEpochRejected(validity))
    Err(@host.CapacityExceeded) => return Err(CapacityExceeded)
    Err(@host.Encoding(@host.Encoding)) => return Err(Encoding)
    Err(@host.Encoding(@host.CapacityExceeded)) => return Err(CapacityExceeded)
  }
  let (key, body, revision, issued_body) = @host.client_submitted_journal_append_rows(
    plan,
  )
  match
    self.database.compare_exchange(
      "client_submitted_intent_custody", "issued", revision, issued_body,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  self.database
  .insert("client_submitted_intents", key, body)
  .map(revision => {
    reference,
    intent,
    run_admission: None,
    revision,
    run_state_original: None,
    run_state_observation: None,
  })
  .map_err(issue => Physical(issue))
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
