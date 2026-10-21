///|
/// Physical rows for the existing Client request/start Owner. A retained
/// admission is not an execution continuation. The caller owns format
/// inspection, fresh bootstrap, current authorization and database cleanup.
struct NativeClientRunJournal {
  database : @sqlite.Database
  max_records : Int
  mut fenced : Bool
  // Physical transaction ownership only; this is not a Run control revision.
  mut operation_active : Bool
  mut transaction_active : Bool
  mut admitted_record : (
    String,
    Bytes,
    Int64,
    RunRecordPolicyValidation,
    NativeClientRunRecord,
  )?
  admitted_publications : Array[
    (String, Array[@publication.CapturedEffectDependencyBody]),
  ]
  // Read-only lookup may join this journal's own publication fence. Mutating
  // nested operations still fail instead of acquiring another transaction.
  mut publication_read_locked : Bool
  mut admitted_adoption : @host.ClientLocalAdoptionCurrentObservation[
    @sqlite.Database,
  ]?
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
  SubmissionReferenceUsed
  NamedSubmission(@host.ClientSubmittedNameIssue)
  SubmissionEpochRejected(@scope.SubmissionEpochValidity)
  UnsupportedPreparation
  MissingEffectMaterialOriginal
  ChangedEffectMaterialOriginal
  PublicationPolicy(@checked.LocalDependencyBodyIssue)
  Checkpoint(NativeClientCheckpointIssue)
  CancellationIdentity(@host.ClientCancellationIdentityIssue)
  CancellationOperation(@host.ClientCancellationOperationIssue)
  PublicationObservation(@publication_store.NativePublicationStoreIssue)
  RunIdIndexIncomplete
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
  run_observation_originals : String?
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
    run_observation_originals=record.run_observation_originals,
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
  read_run_record_in_mode(row, ValidatePublication)
}

///|
// Both modes share every row/local/Effect/Checkpoint/canonical check. Only the
// private wire extractor may defer publication admission inside lookup work.
// Ordinary readers and the initial all-row custody scan keep the original order.
priv enum RunRecordPolicyValidation {
  ValidatePublication
  DeferPublicationWire
}

///|
// A small deferred comparison result, never a permission or retained Record.
priv enum RunPolicyRequestComparison {
  OriginalRequest
  ChangedOriginalIntent
  ForeignOriginalRequest
}

///|
fn read_run_record_in_mode(
  row : @sqlite.NativeJournalValue,
  mode : RunRecordPolicyValidation,
  journal? : NativeClientRunJournal? = None,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  native_timing_count(25)
  let (decoded, local_run_policy_originals, run_observation_originals) = match
    @host.decode_client_run_journal_row_with_observation_originals(row.body) {
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
  match mode {
    ValidatePublication =>
      if decoded.publication_policy_originals is Some(wire) {
        let policies = match journal {
          None => read_run_policy_originals(wire)
          Some(original) => original.publication_originals(wire)
        }
        if policies is Err(_) {
          return Err(CustodyLost)
        }
      }
    DeferPublicationWire => ()
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
    run_observation_originals,
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
  if run_observation_originals is Some(wire) &&
    read_native_run_observation_originals(
      wire,
      definition,
      program_cid=Some(@host.client_request_program_cid(request)),
    )
    is Err(_) {
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
      "client_run_custody",
      "",
      bootstrap_journal_reads(bootstrap),
    ) {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  match
    scan_client_journal_value(
      database,
      "client_runs",
      "",
      bootstrap_journal_reads(bootstrap),
    ) {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  match
    scan_client_journal_value(
      database,
      "client_effect_custody",
      "",
      bootstrap_journal_reads(bootstrap),
    ) {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  for
    table in [
      "client_checkpoint_id_index", "client_run_id_index", "client_run_id_index_coverage",
      "client_run_reference_index", "client_effect_response_meta", "client_effect_response_bytes",
      "client_effect_row_receipt", "client_cancellations", "client_cancel_custody",
      "client_cancel_originals",
    ] {
    match
      scan_client_journal_value(
        database,
        table,
        "",
        bootstrap_journal_reads(bootstrap),
      ) {
      Err(@sqlite.NotFound) => ()
      _ => return Err(CustodyLost)
    }
  }
  match
    insert_bootstrap_journal_value(
      database, "client_cancel_custody", "issued", b"0", bootstrap,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  insert_bootstrap_journal_value(
    database, "client_run_custody", "issued", b"0", bootstrap,
  )
  .map(_ => ())
  .map_err(issue => Physical(issue))
}

///|
fn client_journal_scan(
  database : @sqlite.Database,
  table_name : String,
  cursor : String,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[@host.ClientJournalPhysicalRow?, NativeClientRunJournalIssue] {
  match scan_client_journal_value(database, table_name, cursor, reads) {
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
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[@host.ClientJournalPhysicalRow?, NativeClientRunJournalIssue] {
  match read_client_journal_value(database, table_name, key, reads) {
    Ok(row) => Ok(Some({ key, body: row.body, revision: row.revision, }))
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn run_journal_custody(
  database : @sqlite.Database,
  max_records : Int,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[(Int, Int64), NativeClientRunJournalIssue] {
  @host.inspect_client_run_journal_inventory(
    max_records,
    (table_name, cursor) => {
      client_journal_scan(database, table_name, cursor, reads~)
    },
    (table_name, key) => client_journal_read(database, table_name, key, reads~),
    row => {
      let record = match
        read_run_record({ body: row.body, revision: row.revision, }) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if row.key != @host.client_request_scope_cid(record.request) {
        return Err(CustodyLost)
      }
      match confirm_effect_ledger_custody(database, record, reads~) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      Ok({
        request: record.request,
        definition: record.definition,
        checkpoint: record.checkpoint.map(value => value.effect_ledger),
      })
    },
    () => cancellation_custody(database, max_records, reads~).map(_ => ()),
    CustodyLost,
  )
}

///|
// Ordinary operations authenticate only their selected rows. This monotonic
// issuance anchor bounds append capacity without enumerating unrelated Runs.
// Its revision advances once with each issued record in the same transaction.
fn client_journal_issuance_anchor(
  database : @sqlite.Database,
  table_name : String,
  max_records : Int,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[(Int, Int64), NativeClientRunJournalIssue] {
  let row = match
    read_client_journal_value(database, table_name, "issued", reads) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  let count = match @host.client_journal_issuance_count(row.body, max_records) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if row.revision != count.to_int64() {
    return Err(CustodyLost)
  }
  Ok((count, row.revision))
}

///|
pub fn open_native_client_run_journal(
  database : @sqlite.Database,
  max_records : Int,
) -> Result[NativeClientRunJournal, NativeClientRunJournalIssue] {
  open_native_client_run_journal_with_reads(database, max_records)
}

///|
fn open_native_client_run_journal_with_reads(
  database : @sqlite.Database,
  max_records : Int,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[NativeClientRunJournal, NativeClientRunJournalIssue] {
  if client_journal_transaction_fenced(database, reads) {
    return Err(Fenced)
  }
  if max_records < 1 || max_records > 1024 {
    return Err(CapacityExceeded)
  }
  match
    client_journal_issuance_anchor(
      database,
      "client_run_custody",
      max_records,
      reads~,
    ) {
    Ok(_) =>
      Ok({
        database,
        max_records,
        fenced: false,
        publication_read_locked: false,
        transaction_active: false,
        operation_active: false,
        admitted_publications: [],
        admitted_record: None,
        admitted_adoption: None,
      })
    Err(issue) => Err(issue)
  }
}

///|
fn[T] NativeClientRunJournal::transaction(
  self : NativeClientRunJournal,
  work : () -> Result[T, NativeClientRunJournalIssue],
) -> Result[T, NativeClientRunJournalIssue] {
  self.transaction_with_reads(work)
}

///|
fn[T] NativeClientRunJournal::transaction_with_reads(
  self : NativeClientRunJournal,
  work : () -> Result[T, NativeClientRunJournalIssue],
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[T, NativeClientRunJournalIssue] {
  native_timing_begin(7)
  defer native_timing_end(7)
  if self.fenced || client_journal_transaction_fenced(self.database, reads) {
    return Err(Fenced)
  }
  if self.publication_read_locked || self.transaction_active {
    return Err(Physical(@sqlite.Busy))
  }
  match
    client_journal_transaction_operation(self.database, JournalBegin, reads) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  if !self.operation_active {
    self.admitted_publications.clear()
    self.admitted_record = None
    self.admitted_adoption = None
  }
  self.transaction_active = true
  // The selected operation owns its target admission and local mutation
  // checks. A transaction is not a request to audit unrelated history.
  let result = work()
  self.transaction_active = false
  if !self.operation_active {
    self.admitted_publications.clear()
    self.admitted_record = None
    self.admitted_adoption = None
  }
  match result {
    Ok(value) =>
      match
        client_journal_transaction_operation(
          self.database,
          JournalCommit,
          reads,
        ) {
        Ok(_) => Ok(value)
        Err(_) => {
          self.fenced = true
          fence_client_journal_transactions(self.database, reads)
          Err(TransactionUnknown)
        }
      }
    Err(issue) =>
      match
        client_journal_transaction_operation(
          self.database,
          JournalRollback,
          reads,
        ) {
        Ok(_) => Err(issue)
        Err(_) => {
          self.fenced = true
          fence_client_journal_transactions(self.database, reads)
          Err(TransactionUnknown)
        }
      }
  }
}

///|
// One admitted row in the same Journal transaction. Every use still reads the
// actual row and compares its exact revision and bytes. No absence, authority,
// currentness or physical acknowledgement is cached. The slot is cleared before
// mutation and before transaction completion, including rollback and Unknown.
fn NativeClientRunJournal::admit_retained_record(
  self : NativeClientRunJournal,
  key : String,
  row : @sqlite.NativeJournalValue,
  mode? : RunRecordPolicyValidation = ValidatePublication,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  if (self.transaction_active || self.operation_active) &&
    self.admitted_record
    is Some((original_key, body, revision, admitted_mode, record)) &&
    original_key == key &&
    body == row.body &&
    revision == row.revision {
    if admitted_mode is DeferPublicationWire && mode is ValidatePublication {
      if record.publication_policy_originals is Some(wire) {
        match self.publication_originals(wire) {
          Ok(_) => ()
          Err(_) => return Err(CustodyLost)
        }
      }
      self.admitted_record = Some(
        (key, body, revision, ValidatePublication, record),
      )
    }
    native_timing_count(36)
    return Ok(record)
  }
  let record = match read_run_record_in_mode(row, mode, journal=Some(self)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if self.transaction_active || self.operation_active {
    self.admitted_record = Some((key, row.body, row.revision, mode, record))
  }
  Ok(record)
}

///|
fn NativeClientRunJournal::retained(
  self : NativeClientRunJournal,
  requested : @host.ClientRequestIdentity,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[NativeClientRunRecord?, NativeClientRunJournalIssue] {
  match
    client_journal_issuance_anchor(
      self.database,
      "client_run_custody",
      self.max_records,
      reads~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let row = match
    read_client_journal_value(
      self.database,
      "client_runs",
      @host.client_request_scope_cid(requested),
      reads,
    ) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok(None)
    Err(issue) => return Err(Physical(issue))
  }
  let retained = match
    self.admit_retained_record(@host.client_request_scope_cid(requested), row) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match confirm_effect_ledger_custody(self.database, retained, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match @host.client_request_identity_relation(requested, retained.request) {
    SameRequest => Ok(Some(retained))
    ChangedIntent => Err(ChangedIntent)
    DifferentRequest => Err(CustodyLost)
  }
}

///|
// No Record/Checkpoint/definition escapes this boundary. Hold only the original
// wire and a deferred identity refusal before the work's full Policy admission.
// Policy validation must precede identity refusal, including a row changed by
// the second current callback after the initial normal custody scan.
fn extract_run_policy_wire(
  row : @sqlite.NativeJournalValue,
  requested : @host.ClientRequestIdentity,
) -> Result[(String?, RunPolicyRequestComparison), NativeClientRunJournalIssue] {
  let record = match read_run_record_in_mode(row, DeferPublicationWire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  extract_admitted_run_policy_wire(record, requested)
}

///|
fn extract_admitted_run_policy_wire(
  record : NativeClientRunRecord,
  requested : @host.ClientRequestIdentity,
) -> Result[(String?, RunPolicyRequestComparison), NativeClientRunJournalIssue] {
  let comparison = match
    @host.client_request_identity_relation(requested, record.request) {
    SameRequest => OriginalRequest
    ChangedIntent => ChangedOriginalIntent
    DifferentRequest => ForeignOriginalRequest
  }
  Ok((record.publication_policy_originals, comparison))
}

///|
// Re-read the selected row inside the existing transaction; no Host cache.
// Only lookup work consumes this private raw-wire extraction.
fn NativeClientRunJournal::retained_policy_wire(
  self : NativeClientRunJournal,
  requested : @host.ClientRequestIdentity,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[(String?, RunPolicyRequestComparison), NativeClientRunJournalIssue] {
  let row = match
    read_client_journal_value(
      self.database,
      "client_runs",
      @host.client_request_scope_cid(requested),
      reads,
    ) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  let record = match
    self.admit_retained_record(
      @host.client_request_scope_cid(requested),
      row,
      mode=DeferPublicationWire,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  extract_admitted_run_policy_wire(record, requested)
}

///|
pub fn NativeClientRunJournal::lookup(
  self : NativeClientRunJournal,
  requested : @host.ClientRequestIdentity,
  current_authorization : Bool,
) -> Result[NativeClientRunLookup, NativeClientRunJournalIssue] {
  self.lookup_with_reads(requested, current_authorization)
}

///|
fn NativeClientRunJournal::lookup_with_reads(
  self : NativeClientRunJournal,
  requested : @host.ClientRequestIdentity,
  current_authorization : Bool,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[NativeClientRunLookup, NativeClientRunJournalIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  if self.publication_read_locked {
    return self
      .retained(requested, reads~)
      .map(record => {
        match record {
          Some(value) => Retained(value)
          None => UnresolvedHistory
        }
      })
  }
  self.transaction_with_reads(
    () => {
      self
      .retained(requested, reads~)
      .map(record => {
        match record {
          Some(value) => Retained(value)
          None => UnresolvedHistory
        }
      })
    },
    reads~,
  )
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
  run_observation_originals? : String? = None,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  match self.retained(request, reads~) {
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
    run_journal_custody(self.database, self.max_records, reads~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if count == self.max_records {
    return Err(CapacityExceeded)
  }
  let mut cursor = ""
  while true {
    let row = match
      scan_client_journal_value(self.database, "client_runs", cursor, reads) {
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
    run_observation_originals,
    revision: 0L,
    checkpoint: None,
  }
  let body = match run_record_body(record) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let revision = match
    compare_exchange_client_journal_value(
      self.database,
      "client_run_custody",
      "issued",
      revision,
      @utf8.encode((count + 1).to_string()),
      operations,
    ) {
    Ok(_) =>
      match
        insert_client_journal_value(
          self.database,
          "client_runs",
          @host.client_request_scope_cid(request),
          body,
          operations,
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
  self.save_with_operations(record)
}

///|
fn NativeClientRunJournal::save_with_operations(
  self : NativeClientRunJournal,
  record : NativeClientRunRecord,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  native_timing_count(20)
  if !self.transaction_active {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  let before = match
    read_client_journal_value(
      self.database,
      "client_runs",
      @host.client_request_scope_cid(record.request),
      reads,
    ) {
    Ok(current) if current.revision == record.revision =>
      match
        self.admit_retained_record(
          @host.client_request_scope_cid(record.request),
          current,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    Ok(_) => return Err(Physical(@sqlite.Collision))
    Err(issue) => return Err(Physical(issue))
  }
  match confirm_effect_ledger_custody(self.database, record, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let body = match run_record_body(record) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.admitted_record = None
  let revision = match
    compare_exchange_client_journal_value(
      self.database,
      "client_runs",
      @host.client_request_scope_cid(record.request),
      record.revision,
      body,
      operations,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let next = { ..record, revision, }
  self.save_checkpoint_id_index(before, next, operations~).map(_ => next)
}

///|
pub fn NativeClientRunJournal::reserve_dispatch(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : Bool,
) -> Result[@host.ClientRunStartAction, NativeClientRunJournalIssue] {
  self.reserve_dispatch_with_operations(request, current_authorization)
}

///|
fn NativeClientRunJournal::reserve_dispatch_with_operations(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : Bool,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[@host.ClientRunStartAction, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  self.transaction_with_reads(
    () => {
      let record = match self.retained(request, reads~) {
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
        match
          self.save_with_operations(
            { ..record, dispatch_reserved: true, },
            operations~,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      Ok(action)
    },
    reads~,
  )
}

///|
/// The returned true is available only after the durable physical-start claim
/// commits. A claimed/unknown dispatch can never obtain another true here.
pub fn NativeClientRunJournal::claim_physical_start(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : Bool,
) -> Result[Bool, NativeClientRunJournalIssue] {
  self.claim_physical_start_with_operations(request, current_authorization)
}

///|
fn NativeClientRunJournal::claim_physical_start_with_operations(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  current_authorization : Bool,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Bool, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  self.transaction_with_reads(
    () => {
      let record = match self.retained(request, reads~) {
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
        match
          self.save_with_operations(
            { ..record, physical_start_claimed: true, },
            operations~,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      Ok(eligible)
    },
    reads~,
  )
}
