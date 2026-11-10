///|
/// Physical rows for the existing Client request/start Owner. A retained
/// admission is not an execution continuation. The caller owns format
/// inspection, fresh bootstrap, current authorization and database cleanup.
struct NativeClientRunJournal {
  database : @sqlite.Database
  max_records : Int
  max_retained_intent_bytes : Int64
  mut fenced : Bool
  // Same actual Database format; only acknowledged maintenance advances it.
  mut append_schema : Int
  mut observed_evidence_schema : Int?
  // Physical transaction ownership only; this is not a Run control revision.
  mut operation_active : Bool
  mut transaction_active : Bool
  // Fully admitted selected target of the closed public command. Internal
  // trusted reads consume it until a relevant mutation/failure or command end.
  mut operation_record : NativeClientRunRecord?
  // Same selected Submission and Run relationship for this closed command.
  // Relevant row mutation, failure and operation end retire the typed pair.
  mut operation_submission : (
    NativeClientSubmittedIntentRecord,
    NativeClientRunRecord?,
  )?
  mut admitted_record : (
    String,
    Bytes,
    Int64,
    RunRecordPolicyValidation,
    NativeClientRunRecord,
  )?
  // Immutable header/compiler DATA for this operation, not a retained row or
  // authority. New revisions still admit the outer row and changed metadata.
  mut operation_run_identity : (
    String,
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
    NativeClientStoredRunObservation?,
  )?
  // Pure immutable compilation correspondence, not row custody or permission.
  // Own row revisions do not change it; operation failure/end retires it.
  mut operation_prepared_binding : (
    @host.PreparedClientProgram,
    @host.ClientCompiledRun,
    String,
    String,
    String,
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
  task_materials_cid : String?
  local_run_policy_originals : String?
  run_observation_originals : String?
  observation_original : NativeClientStoredRunObservation?
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
  native_timing_count(45)
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
      task_materials_cid: record.task_materials_cid,
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
  identity? : (@host.ClientRequestIdentity, @publication.PublicationContract)? = None,
  observation? : NativeClientStoredRunObservation? = None,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  native_timing_count(25)
  let decoded = match identity {
    None =>
      @host.decode_client_run_journal_row_with_observation_originals(row.body)
    Some((request, definition)) =>
      @host.decode_client_run_journal_row_with_retained_identity(
        row.body,
        request,
        definition,
      )
  }
  let (decoded, local_run_policy_originals, run_observation_originals) = match
    decoded {
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
  let observation_original = match run_observation_originals {
    None => None
    Some(wire) => {
      let program = Some(@host.client_request_program_cid(request))
      match observation {
        Some(original) if original.matches(wire, definition, program) =>
          Some(original)
        _ =>
          match read_native_stored_run_observation(wire, definition, program) {
            Ok(original) => Some(original)
            Err(_) => return Err(CustodyLost)
          }
      }
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
    task_materials_cid: decoded.task_materials_cid,
    local_run_policy_originals,
    run_observation_originals,
    observation_original,
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
  // The Common decoder already compared its complete canonical outer body
  // with this exact row. Every field above is copied from that admitted row;
  // the Native Checkpoint reader independently checked its nested wire too.
  // No callback or mutation intervenes, so reconstructing the same outer
  // JSON here adds no validation. Native Policy/Effect/observation checks above
  // remain distinct and mandatory.
  Ok(record)
}

///|
/// Only the eventual fresh-format bootstrap may call this initializer. It is
/// private so a caller cannot repair missing custody in an adopted journal.
fn initialize_native_client_run_journal_rows(
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
      "client_cancel_originals", "client_task_run_materials",
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
  observe? : ((String, NativeClientRunRecord) -> Result[
    Unit,
    NativeClientRunJournalIssue,
  ])? = None,
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
      if observe is Some(visit) {
        match visit(row.key, record) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      Ok({
        request: record.request,
        definition: record.definition,
        checkpoint: record.checkpoint.map(value => value.effect_ledger),
        task_materials_cid: record.task_materials_cid,
      })
    },
    () => cancellation_custody(database, max_records, reads~).map(_ => ()),
    CustodyLost,
  )
}

///|
fn confirm_task_material_original_custody(
  database : @sqlite.Database,
  record : NativeClientRunRecord,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  match record.task_materials_cid {
    None => Ok(())
    Some(cid) =>
      @host.read_client_task_material_original(
        @host.client_request_scope_cid(record.request),
        cid,
        (table, key) => client_journal_read(database, table, key, reads~),
        CustodyLost,
      ).map(_ => ())
  }
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
  max_retained_intent_bytes? : Int64 = 67108864L,
) -> Result[NativeClientRunJournal, NativeClientRunJournalIssue] {
  open_native_client_run_journal_with_reads(
    database,
    max_records,
    max_retained_intent_bytes~,
  )
}

///|
fn open_native_client_run_journal_with_reads(
  database : @sqlite.Database,
  max_records : Int,
  reads? : NativeClientJournalReadAccess? = None,
  max_retained_intent_bytes? : Int64 = 67108864L,
) -> Result[NativeClientRunJournal, NativeClientRunJournalIssue] {
  if client_journal_transaction_fenced(database, reads) {
    return Err(Fenced)
  }
  if max_records < 1 || max_retained_intent_bytes < 0L {
    return Err(CapacityExceeded)
  }
  let append_schema = match
    client_journal_run_definition_schema(database, reads) {
    Ok(value) if value == 0 || value == 1 => value
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
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
        max_retained_intent_bytes,
        append_schema,
        observed_evidence_schema: None,
        fenced: false,
        publication_read_locked: false,
        transaction_active: false,
        operation_active: false,
        admitted_publications: [],
        operation_record: None,
        operation_submission: None,
        admitted_record: None,
        operation_run_identity: None,
        operation_prepared_binding: None,
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
// Inherited local/physical fences only. This neither begins a transaction nor
// claims that a later BEGIN will succeed. Pure command metadata can consume
// its already admitted originals without manufacturing another SQL snapshot.
fn NativeClientRunJournal::check_transaction_context(
  self : NativeClientRunJournal,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if self.fenced || client_journal_transaction_fenced(self.database, reads) {
    return Err(Fenced)
  }
  if self.publication_read_locked || self.transaction_active {
    return Err(Physical(@sqlite.Busy))
  }
  Ok(())
}

///|
fn[T] NativeClientRunJournal::transaction_with_reads(
  self : NativeClientRunJournal,
  work : () -> Result[T, NativeClientRunJournalIssue],
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[T, NativeClientRunJournalIssue] {
  native_timing_begin(7)
  defer native_timing_end(7)
  match self.check_transaction_context(reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    client_journal_transaction_operation(self.database, JournalBegin, reads) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  if !self.operation_active {
    self.admitted_publications.clear()
    self.invalidate_operation_record()
    self.admitted_adoption = None
  }
  self.transaction_active = true
  // The selected operation owns its target admission and local mutation
  // checks. A transaction is not a request to audit unrelated history.
  let result = work()
  self.transaction_active = false
  if !self.operation_active {
    self.admitted_publications.clear()
    self.invalidate_operation_record()
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
        Ok(_) => {
          // Existing opt-in diagnostic counters: 4/5 commit success/failure,
          // 6/7 rollback success/failure. None supplies a durable ACK.
          native_timing_count(4)
          Ok(value)
        }
        Err(_) => {
          native_timing_count(5)
          self.invalidate_operation_record()
          self.fenced = true
          fence_client_journal_transactions(self.database, reads)
          Err(TransactionUnknown)
        }
      }
    Err(issue) => {
      // A failed mutation/observation cannot leave a typed target describing
      // uncommitted state available after its rollback or lost return.
      self.invalidate_operation_record()
      match
        client_journal_transaction_operation(
          self.database,
          JournalRollback,
          reads,
        ) {
        Ok(_) => {
          native_timing_count(6)
          Err(issue)
        }
        Err(_) => {
          native_timing_count(7)
          self.fenced = true
          fence_client_journal_transactions(self.database, reads)
          Err(TransactionUnknown)
        }
      }
    }
  }
}

///|
fn NativeClientRunJournal::invalidate_operation_record(
  self : NativeClientRunJournal,
) -> Unit {
  self.invalidate_operation_run()
  self.invalidate_operation_submission()
  self.observed_evidence_schema = None
  self.operation_prepared_binding = None
}

///|
// A deferred Policy lookup may already have observed this exact row. Full
// admission can consume those immutable bytes instead of selecting them again.
// The same mutation/failure/end invalidation clears this existing row slot.
fn NativeClientRunJournal::operation_row(
  self : NativeClientRunJournal,
  key : String,
) -> @sqlite.NativeJournalValue? {
  if self.operation_active &&
    self.admitted_record is Some((original, body, revision, _, _)) &&
    original == key {
    Some({ body, revision, })
  } else {
    None
  }
}

///|
// Reuse the admitted row in the unchanged operation or SQLite snapshot. A
// newly observed row must match its exact revision and bytes before reuse.
// Relevant mutation, failure and operation/transaction end invalidate the
// slot; a retained value supplies no physical cleanup acknowledgement.
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
  let (identity, observation) = if self.transaction_active ||
    self.operation_active {
    match self.operation_run_identity {
      Some((original, request, definition, observation)) if original == key =>
        (Some((request, definition)), observation)
      _ => (None, None)
    }
  } else {
    (None, None)
  }
  let record = match
    read_run_record_in_mode(
      row,
      mode,
      journal=Some(self),
      identity~,
      observation~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if self.transaction_active || self.operation_active {
    self.admitted_record = Some((key, row.body, row.revision, mode, record))
    self.operation_run_identity = Some(
      (key, record.request, record.definition, record.observation_original),
    )
  }
  Ok(record)
}

///|
fn NativeClientRunJournal::retained(
  self : NativeClientRunJournal,
  requested : @host.ClientRequestIdentity,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[NativeClientRunRecord?, NativeClientRunJournalIssue] {
  self.retained_with_issuance(requested, reads~).map(value => value.0)
}

///|
// A target miss and the following append share this actual issuance row in
// the caller's transaction. The coordinate never outlives this synchronous
// call and does not replace the final capacity check or original CAS.
fn NativeClientRunJournal::retained_with_issuance(
  self : NativeClientRunJournal,
  requested : @host.ClientRequestIdentity,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[
  (NativeClientRunRecord?, (Int, Int64)?),
  NativeClientRunJournalIssue,
] {
  if reads is Some(access) && !physical_equal(access.database, self.database) {
    return Err(Physical(@sqlite.Collision))
  }
  if self.fenced || client_journal_transaction_fenced(self.database, reads) {
    return Err(Fenced)
  }
  if self.operation_active &&
    self.operation_record is Some(original) &&
    @host.client_request_scope_cid(requested) ==
    @host.client_request_scope_cid(original.request) {
    return match
      @host.client_request_identity_relation(requested, original.request) {
      SameRequest => Ok((Some(original), None))
      ChangedIntent => Err(ChangedIntent)
      DifferentRequest => Err(CustodyLost)
    }
  }
  let issuance = match
    client_journal_issuance_anchor(
      self.database,
      "client_run_custody",
      self.max_records,
      reads~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let key = @host.client_request_scope_cid(requested)
  let row = match self.operation_row(key) {
    Some(value) => value
    None =>
      match
        read_client_journal_value(self.database, "client_runs", key, reads) {
        Ok(value) => value
        Err(@sqlite.NotFound) => return Ok((None, Some(issuance)))
        Err(issue) => return Err(Physical(issue))
      }
  }
  let retained = match self.admit_retained_record(key, row) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    confirm_task_material_original_custody(self.database, retained, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match confirm_effect_ledger_custody(self.database, retained, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match @host.client_request_identity_relation(requested, retained.request) {
    SameRequest => {
      if self.operation_active {
        self.operation_record = Some(retained)
      }
      Ok((Some(retained), Some(issuance)))
    }
    ChangedIntent => Err(ChangedIntent)
    DifferentRequest => Err(CustodyLost)
  }
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
// Select the original row or reuse its existing operation fact in the same
// transaction. Only lookup work consumes this private raw-wire extraction.
fn NativeClientRunJournal::retained_policy_wire(
  self : NativeClientRunJournal,
  requested : @host.ClientRequestIdentity,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[(String?, RunPolicyRequestComparison), NativeClientRunJournalIssue] {
  if reads is Some(access) && !physical_equal(access.database, self.database) {
    return Err(Physical(@sqlite.Collision))
  }
  if self.fenced || client_journal_transaction_fenced(self.database, reads) {
    return Err(Fenced)
  }
  if self.operation_active &&
    self.operation_record is Some(original) &&
    @host.client_request_scope_cid(requested) ==
    @host.client_request_scope_cid(original.request) {
    return extract_admitted_run_policy_wire(original, requested)
  }
  let key = @host.client_request_scope_cid(requested)
  let row = match self.operation_row(key) {
    Some(value) => value
    None =>
      match
        read_client_journal_value(self.database, "client_runs", key, reads) {
        Ok(value) => value
        Err(@sqlite.NotFound) => return Err(CustodyLost)
        Err(issue) => return Err(Physical(issue))
      }
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
  // This closed operation already owns its original Read and selected facts.
  // A pure lookup must not manufacture another SQLite transaction/frame.
  if self.publication_read_locked || self.operation_active {
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
    self.validate_prepared_run_binding(request, prepared, compiled, definition) {
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
  native_timing_begin(21)
  defer native_timing_end(21)
  match
    @host.validate_client_run_binding(request, prepared, compiled, definition) {
    Ok(_) => Ok(())
    Err(ChangedIntent) => Err(ChangedIntent)
    Err(ForeignRun) => Err(ForeignRun)
  }
}

///|
// Only the unchanged pure join is retained. Callers still observe current
// authorization, actual rows and durable claims at their existing boundaries.
fn NativeClientRunJournal::validate_prepared_run_binding(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  prepared : @host.PreparedClientProgram,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if self.fenced {
    self.operation_prepared_binding = None
    return Err(Fenced)
  }
  let program = @host.client_request_program_cid(request)
  let parameters = @host.client_request_parameters_cid(request)
  let definition_cid = @publication.publication_contract_identity(definition)
  if self.operation_active &&
    self.operation_prepared_binding
    is Some((owner, run, cid, program_cid, parameters_cid)) &&
    physical_equal(owner, prepared) &&
    physical_equal(run, compiled) &&
    cid == definition_cid &&
    program_cid == program &&
    parameters_cid == parameters {
    return Ok(())
  }
  self.operation_prepared_binding = None
  match
    validate_native_client_run_binding(request, prepared, compiled, definition) {
    Err(issue) => Err(issue)
    Ok(_) => {
      if self.operation_active {
        self.operation_prepared_binding = Some(
          (prepared, compiled, definition_cid, program, parameters),
        )
      }
      Ok(())
    }
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
  observation_original? : NativeClientStoredRunObservation? = None,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  if observation_original is Some(original) &&
    !(run_observation_originals is Some(wire) &&
    original.matches(
      wire,
      definition,
      Some(@host.client_request_program_cid(request)),
    )) {
    return Err(ForeignRun)
  }
  let reads = operations.map(value => value.reads)
  let issuance = match self.retained_with_issuance(request, reads~) {
    Err(issue) => return Err(issue)
    Ok((Some(retained), _)) => {
      if @publication.publication_contract_identity(definition) !=
        @publication.publication_contract_identity(retained.definition) {
        return Err(ForeignRun)
      }
      return Ok(retained)
    }
    Ok((None, Some(original))) => original
    Ok((None, None)) => return Err(CustodyLost)
  }
  if self.append_schema != 1 {
    return Err(CustodyLost)
  }
  let (count, revision) = issuance
  if count == self.max_records {
    return Err(CapacityExceeded)
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
    task_materials_cid: None,
    local_run_policy_originals: None,
    run_observation_originals,
    observation_original,
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
        Err(@sqlite.Collision) =>
          return Err(
            self.classify_run_definition_collision(request, definition, reads~),
          )
        Err(issue) => return Err(Physical(issue))
      }
    Err(issue) => return Err(Physical(issue))
  }
  if self.transaction_active || self.operation_active {
    self.operation_run_identity = Some(
      (
        @host.client_request_scope_cid(request),
        request,
        definition,
        observation_original,
      ),
    )
  }
  Ok({ ..record, revision, })
}

///|
// The ordinary successful insert has already enforced uniqueness and needs no
// second lookup. Only its typed Collision selects the exact indexed candidate
// to preserve the original logical ForeignRun refusal. No history is scanned,
// no admission is retried and the surrounding transaction still rolls back.
fn NativeClientRunJournal::classify_run_definition_collision(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  reads? : NativeClientJournalReadAccess? = None,
) -> NativeClientRunJournalIssue {
  if !self.transaction_active || self.append_schema != 1 {
    return CustodyLost
  }
  let definition_cid = @publication.publication_contract_identity(definition)
  let key = match
    client_journal_run_definition_key(self.database, definition_cid, reads) {
    Ok(Some(value)) => value
    Ok(None) => return Physical(@sqlite.Collision)
    Err(issue) => return Physical(issue)
  }
  let row = match
    read_client_journal_value(self.database, "client_runs", key, reads) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return CustodyLost
    Err(issue) => return Physical(issue)
  }
  let original = match self.admit_retained_record(key, row) {
    Ok(value) => value
    Err(issue) => return issue
  }
  if @host.client_request_scope_cid(original.request) != key ||
    @publication.publication_contract_identity(original.definition) !=
    definition_cid ||
    @host.client_request_scope_cid(request) == key {
    return CustodyLost
  }
  match confirm_effect_ledger_custody(self.database, original, reads~) {
    Ok(_) => ForeignRun
    Err(issue) => issue
  }
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
  if record.task_materials_cid != before.task_materials_cid {
    return Err(CustodyLost)
  }
  match confirm_task_material_original_custody(self.database, before, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match confirm_effect_ledger_custody(self.database, record, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let body = match run_record_body(record) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.invalidate_operation_run()
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
  // An unrelated field's CAS spends its own row admission, not the unchanged
  // compiler metadata. Use only the actual pre-CAS reader's typed originals;
  // a copied candidate field cannot supply this retention.
  let observation_original = before.observation_original.filter(original => {
    record.run_observation_originals is Some(wire) &&
    original.matches(
      wire,
      record.definition,
      Some(@host.client_request_program_cid(record.request)),
    )
  })
  let next = { ..record, revision, observation_original, }
  match self.save_checkpoint_id_index(before, next, operations~) {
    Err(issue) => Err(issue)
    Ok(_) => {
      // These opaque identities already belong to the emitted record. Keep
      // them separately from row admission: changed metadata still needs its
      // reader, while equal headers need no second parse or CID validation.
      self.operation_run_identity = Some(
        (
          @host.client_request_scope_cid(next.request),
          next.request,
          next.definition,
          next.observation_original,
        ),
      )
      // A control-only CAS without a Checkpoint changes flags and revision,
      // not its admitted Run or Policy originals. Retain that typed result with
      // the bytes just written; foreign metadata still takes full admission.
      // Rollback, lost COMMIT and operation end clear this same existing slot.
      if run_record_originals_unchanged(before, next) {
        self.admitted_record = Some(
          (
            @host.client_request_scope_cid(next.request),
            body,
            revision,
            ValidatePublication,
            next,
          ),
        )
      }
      Ok(next)
    }
  }
}

///|
// This is a reuse selection for an already admitted record, not admission of
// changed metadata. Identity checks on opaque originals avoid decoding their
// unchanged wire. The existing reader remains responsible for every fallback.
fn run_record_originals_unchanged(
  before : NativeClientRunRecord,
  after : NativeClientRunRecord,
) -> Bool {
  physical_equal(before.request, after.request) &&
  physical_equal(before.definition, after.definition) &&
  before.publication_binding == after.publication_binding &&
  before.publication_policy_originals == after.publication_policy_originals &&
  before.effect_material_originals == after.effect_material_originals &&
  before.local_run_policy_originals == after.local_run_policy_originals &&
  before.run_observation_originals == after.run_observation_originals &&
  before.checkpoint is None &&
  after.checkpoint is None &&
  (!after.physical_start_claimed || after.dispatch_reserved)
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

///|
fn NativeClientRunJournal::invalidate_operation_submission(
  self : NativeClientRunJournal,
) -> Unit {
  self.operation_submission = None
}

///|
// A Run mutation changes the retained relationship, not the already admitted
// Submission row. Reuse its immutable intent/reference and observe only the
// new Run before returning the pair again.
fn NativeClientRunJournal::invalidate_operation_run(
  self : NativeClientRunJournal,
) -> Unit {
  self.operation_record = None
  self.admitted_record = None
  self.operation_run_identity = None
  if self.operation_submission is Some((original, _)) {
    self.operation_submission = Some((original, None))
  }
}
