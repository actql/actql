///|
/// Physical rows for the existing Client request/start Owner. A retained
/// admission is not an execution continuation. The caller owns format
/// inspection, fresh bootstrap, current authorization and database cleanup.
struct NativeClientRunJournal {
  database : @sqlite.Database
  max_records : Int
  mut fenced : Bool
  // Read-only lookup may join this journal's own publication fence. Mutating
  // nested operations still fail instead of acquiring another transaction.
  mut publication_read_locked : Bool
}

///|
pub(all) enum NativeClientRunJournalIssue {
  CustodyLost
  CapacityExceeded
  AuthorizationDenied
  ChangedIntent
  ForeignRun
  Fenced
  TransactionUnknown
  Encoding
  Physical(@sqlite.NativeSqliteIssue)
  Start(@host.ClientRunStartIssue)
  Epoch(NativeClientEpochIssue)
  InvalidSubmission
  SubmissionEpochRejected(@scope.SubmissionEpochValidity)
  UnsupportedPreparation
  Checkpoint(NativeClientCheckpointIssue)
  CancellationIdentity(@host.ClientCancellationIdentityIssue)
  CancellationOperation(@host.ClientCancellationOperationIssue)
  PublicationObservation(@publication_store.NativePublicationStoreIssue)
}

///|
struct NativeClientRunRecord {
  request : @host.ClientRequestIdentity
  definition : @publication.PublicationContract
  dispatch_reserved : Bool
  physical_start_claimed : Bool
  cancellation_requested : Bool
  publication_binding : String?
  revision : Int64
  checkpoint : NativeClientCheckpointRecord?
}

///|
pub enum NativeClientRunLookup {
  // No retained record is not evidence of non-execution or resend permission.
  UnresolvedHistory
  Retained(NativeClientRunRecord)
}

///|
pub fn native_client_run_definition(
  record : NativeClientRunRecord,
) -> @publication.PublicationContract {
  record.definition
}

///|
pub fn native_client_run_record_revision(
  record : NativeClientRunRecord,
) -> Int64 {
  record.revision
}

///|
fn run_record_body(
  record : NativeClientRunRecord,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  let request = match
    @host.client_request_identity_record_wire(record.request) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  try {
    let writer = @encode.writer(131072, 32, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "cancellation_requested")
    @encode.bool_value(writer, record.cancellation_requested)
    @encode.key(writer, "checkpoint")
    match record.checkpoint {
      Some(value) => {
        let body = match checkpoint_record_body(value) {
          Ok(value) => value
          Err(_) => return Err(Encoding)
        }
        @encode.string_value(writer, body)
      }
      None => @encode.null_value(writer)
    }
    @encode.key(writer, "dispatch_reserved")
    @encode.bool_value(writer, record.dispatch_reserved)
    @encode.key(writer, "physical_start_claimed")
    @encode.bool_value(writer, record.physical_start_claimed)
    @encode.key(writer, "publication_binding")
    match record.publication_binding {
      Some(value) => @encode.string_value(writer, value)
      None => @encode.null_value(writer)
    }
    @encode.key(writer, "request")
    @encode.string_value(writer, request)
    @encode.key(writer, "run_definition")
    @encode.string_value(
      writer,
      @publication.publication_contract_json(record.definition),
    )
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-client-run-row/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn read_run_record(
  row : @sqlite.NativeJournalValue,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  let source = match
    @source.parse_json_bytes_preserving(row.body, {
      max_input_bytes: 131072,
      max_nodes: 32,
      max_depth: 4,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 32,
      max_depth: 4,
      max_string_bytes: 131072,
      max_total_string_bytes: 131072,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard @decode.closed_object(cursor, [
      "version", "request", "run_definition", "dispatch_reserved", "physical_start_claimed",
      "cancellation_requested", "checkpoint", "publication_binding",
    ])
    is Ok(object) &&
    epoch_text(object, "version") == Some("actql-native-client-run-row/0.1") &&
    epoch_text(object, "request") is Some(request_wire) &&
    epoch_text(object, "run_definition") is Some(definition_wire) else {
    return Err(CustodyLost)
  }
  let flag = key => {
    @decode.lookup(object, key).bind(value => @decode.boolean(value).to_option())
  }
  guard flag("dispatch_reserved") is Some(dispatch_reserved) &&
    flag("physical_start_claimed") is Some(physical_start_claimed) &&
    flag("cancellation_requested") is Some(cancellation_requested) else {
    return Err(CustodyLost)
  }
  if physical_start_claimed && !dispatch_reserved {
    return Err(CustodyLost)
  }
  let request = match
    @host.admit_client_request_identity_record_wire(request_wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let definition = match
    @publication.admit_publication_contract(
      "run_definition", definition_wire, 65536, 4096, 64,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let record : NativeClientRunRecord = {
    request,
    definition,
    dispatch_reserved,
    physical_start_claimed,
    cancellation_requested,
    publication_binding: match @decode.lookup(object, "publication_binding") {
      Some(value) if @decode.is_null(value) => None
      Some(value) =>
        match @decode.text(value) {
          Ok(text) if text != "" && text.length() <= 4096 => Some(text)
          _ => return Err(CustodyLost)
        }
      None => return Err(CustodyLost)
    },
    revision: row.revision,
    checkpoint: match @decode.lookup(object, "checkpoint") {
      Some(value) if @decode.is_null(value) => None
      Some(value) => {
        let wire = match @decode.text(value) {
          Ok(value) => value
          Err(_) => return Err(CustodyLost)
        }
        match read_checkpoint_record(wire, definition) {
          Ok(value) => Some(value)
          Err(_) => return Err(CustodyLost)
        }
      }
      None => return Err(CustodyLost)
    },
  }
  if record.checkpoint is Some(_) && !physical_start_claimed {
    return Err(CustodyLost)
  }
  if record.checkpoint is Some(checkpoint) &&
    checkpoint.effect_ledger.any(entry => {
      @effect.effect_ledger_entry_scope_cid(entry) !=
      @host.client_request_scope_cid(request)
    }) {
    return Err(CustodyLost)
  }
  match run_record_body(record) {
    Ok(body) if body == row.body => Ok(record)
    _ => Err(CustodyLost)
  }
}

///|
/// Only the eventual fresh-format bootstrap may call this initializer. It is
/// private so a caller cannot repair missing custody in an adopted journal.
fn initialize_native_client_run_journal(
  database : @sqlite.Database,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if database.transaction_fenced() {
    return Err(Fenced)
  }
  match database.scan_after("client_run_custody", "") {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  match database.scan_after("client_runs", "") {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  match database.scan_after("client_effect_custody", "") {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  for
    table in [
      "client_effect_response_meta", "client_effect_response_bytes", "client_effect_row_receipt",
      "client_cancellations", "client_cancel_custody",
    ] {
    match database.scan_after(table, "") {
      Err(@sqlite.NotFound) => ()
      _ => return Err(CustodyLost)
    }
  }
  match database.insert("client_cancel_custody", "issued", b"0") {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  database
  .insert("client_run_custody", "issued", b"0")
  .map(_ => ())
  .map_err(issue => Physical(issue))
}

///|
fn run_journal_custody(
  database : @sqlite.Database,
  max_records : Int,
) -> Result[(Int, Int64), NativeClientRunJournalIssue] {
  match database.scan_after("client_run_custody", "") {
    Ok(row) if row.key == "issued" => ()
    _ => return Err(CustodyLost)
  }
  match database.scan_after("client_run_custody", "issued") {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  let retained = match database.read("client_run_custody", "issued") {
    Ok(value) => value
    _ => return Err(CustodyLost)
  }
  let text = @utf8.decode(retained.body) catch { _ => return Err(CustodyLost) }
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
  if count < 0 || count > max_records || count.to_string() != text {
    return Err(CustodyLost)
  }
  let mut cursor = ""
  let mut observed = 0
  let definitions : Map[String, Bool] = Map([], capacity=max_records)
  let checkpoint_scopes : Map[String, Bool] = Map([], capacity=max_records)
  let responses : Map[String, Bool] = Map([], capacity=max_records)
  let receipts : Map[String, Bool] = Map([], capacity=max_records)
  while true {
    let row = match database.scan_after("client_runs", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    observed = observed + 1
    if observed > count {
      return Err(CustodyLost)
    }
    let record = match
      read_run_record({ body: row.body, revision: row.revision, }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if row.key != @host.client_request_scope_cid(record.request) {
      return Err(CustodyLost)
    }
    match confirm_effect_ledger_custody(database, record) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    if record.checkpoint is Some(checkpoint) {
      checkpoint_scopes[row.key] = true
      for entry in checkpoint.effect_ledger {
        let state = @effect.effect_ledger_entry_state_code(entry)
        if state >= 2 && state <= 4 {
          guard entry.outcome_receipt_cid is Some(cid) &&
            !receipts.contains(cid) else {
            return Err(CustodyLost)
          }
          receipts[cid] = true
        }
        if @effect.effect_ledger_entry_state_code(entry) != 1 {
          continue
        }
        let cid = @effect.effect_ledger_entry_cid(entry)
        match database.read("client_effect_response_meta", cid) {
          Ok(_) => {
            if responses.contains(cid) {
              return Err(CustodyLost)
            }
            responses[cid] = true
          }
          Err(@sqlite.NotFound) => ()
          Err(issue) => return Err(Physical(issue))
        }
      }
    }
    let definition = @publication.publication_contract_identity(
      record.definition,
    )
    if definitions.contains(definition) {
      return Err(CustodyLost)
    }
    definitions[definition] = true
    cursor = row.key
  }
  if observed != count {
    return Err(CustodyLost)
  }
  cursor = ""
  let mut witnesses = 0
  while true {
    let row = match database.scan_after("client_effect_custody", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    witnesses += 1
    if witnesses > observed || !checkpoint_scopes.contains(row.key) {
      return Err(CustodyLost)
    }
    cursor = row.key
  }
  if witnesses != checkpoint_scopes.length() {
    return Err(CustodyLost)
  }
  // No unattached response is adopted, including a pair left behind without
  // its original dispatch or Run. All expected pairs were authenticated above.
  for table in ["client_effect_response_meta", "client_effect_response_bytes"] {
    let mut cursor = ""
    let mut response_count = 0
    while true {
      let row = match database.scan_after(table, cursor) {
        Ok(value) => value
        Err(@sqlite.NotFound) => break
        Err(issue) => return Err(Physical(issue))
      }
      response_count += 1
      if response_count > responses.length() ||
        !responses.contains(row.key) ||
        row.revision != 0L {
        return Err(CustodyLost)
      }
      cursor = row.key
    }
    if response_count != responses.length() {
      return Err(CustodyLost)
    }
  }
  let mut receipt_cursor = ""
  let mut receipt_count = 0
  while true {
    let row = match
      database.scan_after("client_effect_row_receipt", receipt_cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    receipt_count += 1
    if receipt_count > receipts.length() ||
      !receipts.contains(row.key) ||
      row.revision != 0L {
      return Err(CustodyLost)
    }
    receipt_cursor = row.key
  }
  if receipt_count != receipts.length() {
    return Err(CustodyLost)
  }
  match cancellation_custody(database, max_records) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok((count, retained.revision))
}

///|
pub fn open_native_client_run_journal(
  database : @sqlite.Database,
  max_records : Int,
) -> Result[NativeClientRunJournal, NativeClientRunJournalIssue] {
  if database.transaction_fenced() {
    return Err(Fenced)
  }
  if max_records < 1 || max_records > 1024 {
    return Err(CapacityExceeded)
  }
  match run_journal_custody(database, max_records) {
    Ok(_) =>
      Ok({
        database,
        max_records,
        fenced: false,
        publication_read_locked: false,
      })
    Err(issue) => Err(issue)
  }
}

///|
fn[T] NativeClientRunJournal::transaction(
  self : NativeClientRunJournal,
  work : () -> Result[T, NativeClientRunJournalIssue],
) -> Result[T, NativeClientRunJournalIssue] {
  if self.fenced || self.database.transaction_fenced() {
    return Err(Fenced)
  }
  if self.publication_read_locked {
    return Err(Physical(@sqlite.Busy))
  }
  match self.database.begin_immediate() {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  let result = match run_journal_custody(self.database, self.max_records) {
    Ok(_) => work()
    Err(issue) => Err(issue)
  }
  match result {
    Ok(value) =>
      match self.database.commit() {
        Ok(_) => Ok(value)
        Err(_) => {
          self.fenced = true
          self.database.fence_transactions()
          Err(TransactionUnknown)
        }
      }
    Err(issue) =>
      match self.database.rollback() {
        Ok(_) => Err(issue)
        Err(_) => {
          self.fenced = true
          self.database.fence_transactions()
          Err(TransactionUnknown)
        }
      }
  }
}

///|
fn NativeClientRunJournal::retained(
  self : NativeClientRunJournal,
  requested : @host.ClientRequestIdentity,
) -> Result[NativeClientRunRecord?, NativeClientRunJournalIssue] {
  let row = match
    self.database.read("client_runs", @host.client_request_scope_cid(requested)) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok(None)
    Err(issue) => return Err(Physical(issue))
  }
  let retained = match read_run_record(row) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @host.client_request_identity_relation(requested, retained.request) {
    SameRequest => Ok(Some(retained))
    ChangedIntent => Err(ChangedIntent)
    DifferentRequest => Err(CustodyLost)
  }
}

///|
pub fn NativeClientRunJournal::lookup(
  self : NativeClientRunJournal,
  requested : @host.ClientRequestIdentity,
  current_authorization : Bool,
) -> Result[NativeClientRunLookup, NativeClientRunJournalIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  if self.publication_read_locked {
    return self
      .retained(requested)
      .map(record => {
        match record {
          Some(value) => Retained(value)
          None => UnresolvedHistory
        }
      })
  }
  self.transaction(() => {
    self
    .retained(requested)
    .map(record => {
      match record {
        Some(value) => Retained(value)
        None => UnresolvedHistory
      }
    })
  })
}

///|
/// Persist one checked Run binding and its independent issuance count in the
/// same transaction. Compilation and request intent are rechecked by Owners.
/// This method does not record Submission receipt or authorize physical work.
pub fn NativeClientRunJournal::bind_run(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  current_authorization : Bool,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  match
    validate_native_client_run_binding(request, prepared, compiled, definition) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.transaction(() => self.bind_run_locked(request, definition))
}

///|
/// Both ordinary Run binding and original Submission acceptance use the same
/// checked compilation and definition owner; no alternate admission path.
fn validate_native_client_run_binding(
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let identity = @host.prepared_client_identity(prepared)
  if !@host.client_compiled_run_matches(compiled, prepared) ||
    @host.client_request_program_cid(request) != identity.program_definition_cid ||
    @host.client_request_parameters_cid(request) !=
    identity.parameter_values_cid {
    return Err(ChangedIntent)
  }
  if @host.check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(ForeignRun)
  }
  Ok(())
}

///|
/// The caller holds the existing journal transaction and has validated the
/// exact checked binding. This helper neither begins nor commits a transaction.
fn NativeClientRunJournal::bind_run_locked(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  match self.retained(request) {
    Err(issue) => return Err(issue)
    Ok(Some(retained)) => {
      if @publication.publication_contract_identity(definition) !=
        @publication.publication_contract_identity(retained.definition) {
        return Err(ForeignRun)
      }
      return Ok(retained)
    }
    Ok(None) => ()
  }
  let (count, revision) = match
    run_journal_custody(self.database, self.max_records) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if count == self.max_records {
    return Err(CapacityExceeded)
  }
  let mut cursor = ""
  while true {
    let row = match self.database.scan_after("client_runs", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    let other = match
      read_run_record({ body: row.body, revision: row.revision, }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if @publication.publication_contract_identity(other.definition) ==
      @publication.publication_contract_identity(definition) {
      return Err(ForeignRun)
    }
    cursor = row.key
  }
  let record : NativeClientRunRecord = {
    request,
    definition,
    dispatch_reserved: false,
    physical_start_claimed: false,
    cancellation_requested: false,
    publication_binding: None,
    revision: 0L,
    checkpoint: None,
  }
  let body = match run_record_body(record) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let revision = match
    self.database.compare_exchange(
      "client_run_custody",
      "issued",
      revision,
      @utf8.encode((count + 1).to_string()),
    ) {
    Ok(_) =>
      match
        self.database.insert(
          "client_runs",
          @host.client_request_scope_cid(request),
          body,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Physical(issue))
      }
    Err(issue) => return Err(Physical(issue))
  }
  Ok({ ..record, revision, })
}

///|
fn NativeClientRunJournal::save(
  self : NativeClientRunJournal,
  record : NativeClientRunRecord,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  match
    self.database.read(
      "client_runs",
      @host.client_request_scope_cid(record.request),
    ) {
    Ok(current) if current.revision == record.revision => ()
    Ok(_) => return Err(Physical(@sqlite.Collision))
    Err(issue) => return Err(Physical(issue))
  }
  match confirm_effect_ledger_custody(self.database, record) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let body = match run_record_body(record) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.database
  .compare_exchange(
    "client_runs",
    @host.client_request_scope_cid(record.request),
    record.revision,
    body,
  )
  .map(revision => { ..record, revision, })
  .map_err(issue => Physical(issue))
}

///|
pub fn NativeClientRunJournal::reserve_dispatch(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : Bool,
) -> Result[@host.ClientRunStartAction, NativeClientRunJournalIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => {
    let record = match self.retained(request) {
      Ok(Some(record)) => record
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    let action = match
      @host.prepare_client_run_start(
        request,
        record.request,
        record.definition,
        @publication.publication_contract_identity(record.definition),
        record.dispatch_reserved,
        current_authorization,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Start(issue))
    }
    if action == @host.ReserveDispatch {
      match self.save({ ..record, dispatch_reserved: true, }) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    Ok(action)
  })
}

///|
/// The returned true is available only after the durable physical-start claim
/// commits. A claimed/unknown dispatch can never obtain another true here.
pub fn NativeClientRunJournal::claim_physical_start(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : Bool,
) -> Result[Bool, NativeClientRunJournalIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => {
    let record = match self.retained(request) {
      Ok(Some(record)) => record
      Ok(None) => return Err(CustodyLost)
      Err(issue) => return Err(issue)
    }
    let eligible = match
      @host.prepare_client_run_physical_start(
        request,
        record.request,
        record.definition,
        @publication.publication_contract_identity(record.definition),
        record.dispatch_reserved,
        !record.physical_start_claimed,
        current_authorization,
        cancellation_requested=record.cancellation_requested,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Start(issue))
    }
    if eligible {
      // A waiting/resuming continuation is owned by its original Checkpoint;
      // the initial physical-start seam cannot dispatch it again.
      if record.checkpoint is Some(_) {
        return Err(Checkpoint(NeedsOriginalContinuation))
      }
      match self.save({ ..record, physical_start_claimed: true, }) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    Ok(eligible)
  })
}
