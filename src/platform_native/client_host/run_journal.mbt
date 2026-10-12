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
  MissingEffectMaterialOriginal
  ChangedEffectMaterialOriginal
  PublicationPolicy(@checked.LocalDependencyBodyIssue)
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
  publication_policy_originals : String?
  effect_material_originals : String?
  local_run_policy_originals : String?
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
  let checkpoint = match record.checkpoint {
    Some(value) =>
      match checkpoint_record_body(value) {
        Ok(body) => Some(body)
        Err(_) => return Err(Encoding)
      }
    None => None
  }
  @host.client_run_journal_row_body(
    {
      request: record.request,
      definition: record.definition,
      dispatch_reserved: record.dispatch_reserved,
      physical_start_claimed: record.physical_start_claimed,
      cancellation_requested: record.cancellation_requested,
      publication_binding: record.publication_binding,
      publication_policy_originals: record.publication_policy_originals,
      effect_material_originals: record.effect_material_originals,
      checkpoint,
    },
    local_run_policy_originals=record.local_run_policy_originals,
  ).map_err(issue => {
    match issue {
      Encoding => Encoding
      CapacityExceeded => CapacityExceeded
    }
  })
}

///|
fn read_run_record(
  row : @sqlite.NativeJournalValue,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  let (decoded, local_run_policy_originals) = match
    @host.decode_client_run_journal_row_with_local_policy(row.body) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let request = decoded.request
  let definition = decoded.definition
  let physical_start_claimed = decoded.physical_start_claimed
  if local_run_policy_originals is Some(wire) &&
    @host.validate_client_local_run_policy_original_run(
      @utf8.encode(wire),
      request,
      definition,
    )
    is Err(_) {
    return Err(CustodyLost)
  }
  if decoded.publication_policy_originals is Some(wire) &&
    read_run_policy_originals(wire) is Err(_) {
    return Err(CustodyLost)
  }
  if decoded.effect_material_originals is Some(wire) &&
    read_effect_material_original_packet(wire) is Err(_) {
    return Err(CustodyLost)
  }
  let checkpoint = match decoded.checkpoint {
    None => None
    Some(wire) =>
      match read_checkpoint_record(wire, definition) {
        Ok(value) => Some(value)
        Err(_) => return Err(CustodyLost)
      }
  }
  let record : NativeClientRunRecord = {
    request,
    definition,
    dispatch_reserved: decoded.dispatch_reserved,
    physical_start_claimed,
    cancellation_requested: decoded.cancellation_requested,
    publication_binding: decoded.publication_binding,
    publication_policy_originals: decoded.publication_policy_originals,
    effect_material_originals: decoded.effect_material_originals,
    local_run_policy_originals,
    revision: row.revision,
    checkpoint,
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
      "client_cancellations", "client_cancel_custody", "client_cancel_originals",
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
fn client_journal_scan(
  database : @sqlite.Database,
  table_name : String,
  cursor : String,
) -> Result[@host.ClientJournalPhysicalRow?, NativeClientRunJournalIssue] {
  match database.scan_after(table_name, cursor) {
    Ok(row) =>
      Ok(Some({ key: row.key, body: row.body, revision: row.revision, }))
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn client_journal_read(
  database : @sqlite.Database,
  table_name : String,
  key : String,
) -> Result[@host.ClientJournalPhysicalRow?, NativeClientRunJournalIssue] {
  match database.read(table_name, key) {
    Ok(row) => Ok(Some({ key, body: row.body, revision: row.revision, }))
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn run_journal_custody(
  database : @sqlite.Database,
  max_records : Int,
) -> Result[(Int, Int64), NativeClientRunJournalIssue] {
  @host.inspect_client_run_journal_inventory(
    max_records,
    (table_name, cursor) => client_journal_scan(database, table_name, cursor),
    (table_name, key) => client_journal_read(database, table_name, key),
    row => {
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
      Ok({
        request: record.request,
        definition: record.definition,
        checkpoint: record.checkpoint.map(value => value.effect_ledger),
      })
    },
    () => cancellation_custody(database, max_records).map(_ => ()),
    CustodyLost,
  )
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
  match
    @host.validate_client_run_binding(request, prepared, compiled, definition) {
    Ok(_) => Ok(())
    Err(ChangedIntent) => Err(ChangedIntent)
    Err(ForeignRun) => Err(ForeignRun)
  }
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
    publication_policy_originals: None,
    effect_material_originals: None,
    local_run_policy_originals: None,
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
