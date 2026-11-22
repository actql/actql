///|
/// Immutable original-operation custody, not a physical stop or terminal Run.
pub type NativeClientCancellationRecord = @host.ClientCancellationJournalEncoding

///|
pub enum NativeClientCancellationLookup {
  UnresolvedCancellationHistory
  OriginalCancellation(NativeClientCancellationRecord)
}

///|
pub fn native_client_cancellation_action(
  value : NativeClientCancellationRecord,
) -> @host.ClientRunCancellationAction {
  value.action
}

///|
pub fn native_client_cancellation_revision(
  value : NativeClientCancellationRecord,
) -> Int64 {
  value.observed_revision
}

///|
/// Private SQLite index only. Semantic key/intent comparison remains with the
/// existing cancellation Owner. This checksum grants no authority or custody.
fn cancellation_index(
  namespace_id : String,
  authority : String,
  cancel_id : String,
) -> String? {
  @host.client_cancellation_journal_index(namespace_id, authority, cancel_id)
}

///|
fn read_cancellation(
  row : @sqlite.NativeJournalValue,
) -> Result[NativeClientCancellationRecord, NativeClientRunJournalIssue] {
  @host.decode_client_cancellation_journal_row({
    key: "",
    body: row.body,
    revision: row.revision,
  }).map_err(_ => CustodyLost)
}

///|
/// Retained issuance witness detects missing operations independently of Run
/// flags. Missing feature custody cannot be initialized or interpreted as an
/// empty cancellation history by any public operation.
fn cancellation_custody(
  database : @sqlite.Database,
  max_records : Int,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[(Int, Int64), NativeClientRunJournalIssue] {
  @host.inspect_client_cancellation_journal_inventory(
    max_records,
    (table, cursor) => {
      match scan_client_journal_value(database, table, cursor, reads) {
        Ok(row) =>
          Ok(Some({ key: row.key, body: row.body, revision: row.revision, }))
        Err(@sqlite.NotFound) => Ok(None)
        // Preserve this Native Owner's original marker-query disposition.
        Err(_) if table == "client_cancel_custody" => Err(CustodyLost)
        Err(issue) => Err(Physical(issue))
      }
    },
    (table, key) => {
      match read_client_journal_value(database, table, key, reads) {
        Ok(row) => Ok(Some({ key, body: row.body, revision: row.revision, }))
        Err(@sqlite.NotFound) => Ok(None)
        Err(_) if table == "client_cancel_originals" || table == "client_runs" =>
          Err(CustodyLost)
        Err(issue) => Err(Physical(issue))
      }
    },
    row => {
      // The original nested/current metadata validators and their funded
      // constructors stay with this same Native Journal, before projection.
      match
        read_run_record(
          { body: row.body, revision: row.revision, },
          companion_read=Some((database, reads)),
          before_construction=run_decode_construction(database, reads),
          before_metadata_construction=run_metadata_construction(
            database, reads,
          ),
        ) {
        Ok(run) =>
          Ok({
            request: run.request,
            definition: run.definition,
            cancellation_requested: run.cancellation_requested,
          })
        Err(_) => Err(CustodyLost)
      }
    },
    CustodyLost,
  )
}

///|
/// Borrow the existing Store only for current-authorized original-Run lookup.
/// No process-local terminal Bool or foreign publication can enter cancellation.
struct NativeClientCancellationPublication {
  binding : String?
  observe : (NativeClientRunRecord) -> Result[Bool, NativeClientRunJournalIssue]
}

///|
pub fn install_native_client_cancellation_publication(
  store : @publication_store.Store,
  namespace_id : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[NativeClientCancellationPublication, NativeClientRunJournalIssue] {
  if namespace_id == "" || max_wire_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(Encoding)
  }
  let (authority, device, inode) = match store.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(PublicationObservation(issue))
  }
  let binding = match
    installed_publication_binding(namespace_id, authority, device, inode) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    binding: Some(binding),
    observe: run => {
      store
      .inspect_committed_publication(
        namespace_id,
        @host.client_request_authority_scope_cid(run.request),
        @publication.publication_contract_identity(run.definition),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      .map(value => value is Some(_))
      .map_err(issue => PublicationObservation(issue))
    },
  })
}

///|
/// Same retained binding for cancellation and original-Submission reads.
/// Values are preserved; this is physical custody, not configuration identity.
fn installed_publication_binding(
  namespace_id : String,
  authority : String,
  device : UInt64,
  inode : UInt64,
) -> Result[String, NativeClientRunJournalIssue] {
  try {
    let writer = @encode.writer(4096, 8, 2)
    @encode.begin_array(writer)
    for
      value in [namespace_id, authority, device.to_string(), inode.to_string()] {
      @encode.string_value(writer, value)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn cancellation_run_operation_facts(
  run : NativeClientRunRecord,
) -> @host.ClientCancellationRunOperationFacts {
  {
    request: run.request,
    definition: run.definition,
    revision: run.revision,
    cancellation_requested: run.cancellation_requested,
    publication_binding: run.publication_binding,
  }
}

///|
fn cancellation_operation_issue(
  issue : @host.ClientCancellationJournalOperationIssue[
    NativeClientRunJournalIssue,
  ],
) -> NativeClientRunJournalIssue {
  match issue {
    @host.Observation(original) => original
    @host.CustodyLost => CustodyLost
    @host.Encoding => Encoding
    @host.CapacityExceeded => CapacityExceeded
    @host.AuthorizationDenied => AuthorizationDenied
    @host.ChangedIntent => ChangedIntent
    @host.Identity(original) => CancellationIdentity(original)
    @host.Operation(original) => CancellationOperation(original)
  }
}

///|
fn NativeClientRunJournal::cancellation_original(
  self : NativeClientRunJournal,
  key : String,
  reads : NativeClientJournalReadAccess?,
) -> Result[NativeClientCancellationRecord?, NativeClientRunJournalIssue] {
  match
    read_client_journal_value(self.database, "client_cancellations", key, reads) {
    Ok(row) => read_cancellation(row).map(value => Some(value))
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
pub fn NativeClientRunJournal::cancel_operation(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
  current : () -> Bool,
  publication : NativeClientCancellationPublication,
) -> Result[NativeClientCancellationRecord, NativeClientRunJournalIssue] {
  self.cancel_operation_with_operations(
    request, namespace_id, cancel_id, expected_revision, current, publication,
  )
}

///|
// Route the same cancellation Owner through this Journal's original SQL
// operations. No callback here creates a grant, Store or physical stop.
fn NativeClientRunJournal::cancel_operation_with_operations(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
  current : () -> Bool,
  publication : NativeClientCancellationPublication,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientCancellationRecord, NativeClientRunJournalIssue] {
  let reads = operations.map(value => value.reads)
  if reads is Some(access) && !physical_equal(access.database, self.database) {
    return Err(Physical(@sqlite.Collision))
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  if self.fenced || client_journal_transaction_fenced(self.database, reads) {
    return Err(Fenced)
  }
  guard cancellation_index(
      namespace_id,
      @host.client_request_authority_scope_cid(request),
      cancel_id,
    )
    is Some(_) else {
    return Err(Encoding)
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction_with_reads(
    () => {
      let selected = match
        @host.prepare_client_cancellation_journal_append(
          request,
          namespace_id,
          cancel_id,
          expected_revision,
          self.max_records,
          publication.binding,
          () => cancellation_custody(self.database, self.max_records, reads~),
          () => self.retained(request, reads~),
          cancellation_run_operation_facts,
          key => self.cancellation_original(key, reads),
          publication.observe,
          current,
        ) {
        Ok(value) => value
        Err(issue) => return Err(cancellation_operation_issue(issue))
      }
      match selected {
        @host.RetainedCancellation(original) => Ok(original)
        @host.AppendCancellation(plan) => {
          let run = @host.client_cancellation_append_original(plan)
          let record = @host.client_cancellation_append_record(plan)
          if record.action == @host.AcceptCancellation {
            let saved = match
              self.save_with_operations(
                { ..run, cancellation_requested: true, },
                operations~,
              ) {
              Ok(value) => value
              Err(issue) => return Err(issue)
            }
            // The candidate predicts no physical ACK. Check the revision
            // returned by the original actual CAS before storing its outcome.
            if saved.revision != record.observed_revision {
              return Err(CustodyLost)
            }
          }
          guard @host.client_cancellation_append_rows(plan)
            is Some((key, body, original_body, witness_revision, issued_body)) else {
            return Err(Encoding)
          }
          match
            insert_client_journal_value(
              self.database,
              "client_cancellations",
              key,
              body,
              operations,
            ) {
            Ok(_) => ()
            Err(issue) => return Err(Physical(issue))
          }
          match
            insert_client_journal_value(
              self.database,
              "client_cancel_originals",
              key,
              original_body,
              operations,
            ) {
            Ok(_) => ()
            Err(issue) => return Err(Physical(issue))
          }
          match
            compare_exchange_client_journal_value(
              self.database,
              "client_cancel_custody",
              "issued",
              witness_revision,
              issued_body,
              operations,
            ) {
            Ok(_) => Ok(record)
            Err(issue) => Err(Physical(issue))
          }
        }
      }
    },
    reads~,
  )
}

///|
/// Observe only the original cancellation key/intent under current authority.
/// Lookup never invokes the cancellation action, physical stop or a new Run.
pub fn NativeClientRunJournal::lookup_cancellation(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
  current : () -> Bool,
) -> Result[NativeClientCancellationLookup, NativeClientRunJournalIssue] {
  self.lookup_cancellation_with_reads(
    request, namespace_id, cancel_id, expected_revision, current,
  )
}

///|
// Observation of the same immutable cancellation key in the entered Read.
fn NativeClientRunJournal::lookup_cancellation_with_reads(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
  current : () -> Bool,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[NativeClientCancellationLookup, NativeClientRunJournalIssue] {
  if reads is Some(access) && !physical_equal(access.database, self.database) {
    return Err(Physical(@sqlite.Collision))
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction_with_reads(
    () => {
      @host.lookup_client_cancellation_journal_original(
        request,
        namespace_id,
        cancel_id,
        expected_revision,
        () => cancellation_custody(self.database, self.max_records, reads~),
        () => self.retained(request, reads~),
        cancellation_run_operation_facts,
        key => self.cancellation_original(key, reads),
        current,
      )
      .map(value => {
        match value {
          @host.UnresolvedCancellationHistory => UnresolvedCancellationHistory
          @host.OriginalCancellation(original) => OriginalCancellation(original)
        }
      })
      .map_err(cancellation_operation_issue)
    },
    reads~,
  )
}
