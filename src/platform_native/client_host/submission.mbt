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
fn submission_value(wire : String) -> @canonical.CanonicalValue? {
  let source = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
    max_input_bytes: 4096,
    max_nodes: 32,
    max_depth: 4,
  }).to_option()
  source.bind(value => {
    Some(@canonical.from_source(value, 32, 4, 4096, data_keys=true)) catch {
      _ => None
    }
  })
}

///|
pub fn prepare_native_client_submission_reference(
  epoch : NativeClientSubmissionEpoch,
  nonce : String,
) -> Result[NativeClientSubmissionReference, NativeClientRunJournalIssue] {
  let request_id = match @scope.submission_request_id(epoch.body, nonce) {
    Ok(value) => value
    Err(_) => return Err(InvalidSubmission)
  }
  guard submission_value(epoch.wire) is Some(body) else {
    return Err(InvalidSubmission)
  }
  try {
    let writer = @encode.writer(4096, 32, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "epoch")
    @canonical.emit_value(body, writer)
    @encode.key(writer, "nonce")
    @encode.string_value(writer, nonce)
    @encode.end_object(writer)
    let wire = @encode.finish(writer)
    // Retain canonical token bytes without normalizing any nonce value.
    let epoch_wire = @canonical.stringify_value(body, 4096, 32, 4)
    let epoch = match admit_native_client_submission_epoch(epoch_wire) {
      Ok(value) => value
      Err(issue) => return Err(Epoch(issue))
    }
    Ok({ epoch, request_id, wire, })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn admit_native_client_submission_reference(
  wire : String,
) -> Result[NativeClientSubmissionReference, NativeClientRunJournalIssue] {
  guard submission_value(wire) is Some(value) &&
    @canonical.object_field_count(value) == Some(2) &&
    @canonical.object_field(value, "epoch") is Some(epoch) &&
    @canonical.object_field(value, "nonce") is Some(@canonical.String(nonce)) else {
    return Err(InvalidSubmission)
  }
  let epoch_wire = @canonical.stringify_value(epoch, 4096, 32, 4) catch {
    _ => return Err(InvalidSubmission)
  }
  let epoch = match admit_native_client_submission_epoch(epoch_wire) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(issue))
  }
  prepare_native_client_submission_reference(epoch, nonce)
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
  let wire = @host.client_submitted_intent_wire(intent)
  // This physical profile is explicitly finite. Capacity does not classify
  // the caller's Program as invalid or provide permission to retry it.
  if @utf8.encode(wire).length() > 65536 {
    return Err(CapacityExceeded)
  }
  try {
    let writer = @encode.writer(262144, 16, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "intent")
    @encode.string_value(writer, wire)
    @encode.key(writer, "phase")
    @encode.string_value(
      writer,
      if run_admission is Some(_) {
        "ready"
      } else {
        "preparing"
      },
    )
    @encode.key(writer, "reference")
    @encode.string_value(writer, reference.wire)
    if run_admission is Some(admission) {
      let wire = match submitted_run_admission_body(admission) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      @encode.key(writer, "run_admission")
      @encode.string_value(writer, wire)
    }
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-client-submitted-intent-row/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn read_submitted_intent(
  row : @sqlite.NativeJournalValue,
) -> Result[NativeClientSubmittedIntentRecord, NativeClientRunJournalIssue] {
  let source = @source.parse_json_bytes_preserving(row.body, {
    max_input_bytes: 262144,
    max_nodes: 16,
    max_depth: 2,
  }).to_option()
  guard source is Some(source) &&
    @decode.admit(source, {
      max_nodes: 16,
      max_depth: 2,
      max_string_bytes: 131072,
      max_total_string_bytes: 262144,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "intent", "phase", "reference", "run_admission", "version",
    ])
    is Ok(object) &&
    epoch_text(object, "version") ==
    Some("actql-native-client-submitted-intent-row/0.1") &&
    epoch_text(object, "phase") is Some(phase) &&
    epoch_text(object, "reference") is Some(reference_wire) &&
    epoch_text(object, "intent") is Some(intent_wire) else {
    return Err(CustodyLost)
  }
  let reference = match
    admit_native_client_submission_reference(reference_wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let intent = match
    @host.prepare_client_submitted_intent(intent_wire, 65536, 65536, 64) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let run_admission = match @decode.lookup(object, "run_admission") {
    None => None
    Some(value) => {
      guard @decode.text(value) is Ok(wire) else { return Err(CustodyLost) }
      match read_submitted_run_admission(wire) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
    }
  }
  if phase != (if run_admission is Some(_) { "ready" } else { "preparing" }) ||
    !@host.client_submitted_intent_transition(phase, phase) {
    return Err(CustodyLost)
  }
  match submitted_intent_body(reference, intent, run_admission~) {
    Ok(body) if body == row.body =>
      Ok({ reference, intent, run_admission, revision: row.revision, })
    _ => Err(CustodyLost)
  }
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
  let text = @utf8.decode(custody.body) catch { _ => return Err(CustodyLost) }
  if text.is_empty() || text.length() > 4 {
    return Err(CustodyLost)
  }
  let mut count = 0
  for unit in text {
    let digit = unit.to_int() - 48
    if digit < 0 || digit > 9 {
      return Err(CustodyLost)
    }
    count = count * 10 + digit
  }
  if count > self.max_records || count.to_string() != text {
    return Err(CustodyLost)
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
