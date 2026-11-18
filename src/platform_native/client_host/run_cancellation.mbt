///|
/// Immutable original-operation custody, not a physical stop or terminal Run.
type NativeClientCancellationRecord = @host.ClientCancellationJournalEncoding

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
fn cancellation_body(value : NativeClientCancellationRecord) -> Bytes? {
  @host.client_cancellation_journal_row_body(value)
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
      let (issued, witness_revision) = match
        cancellation_custody(self.database, self.max_records, reads~) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let run = match self.retained(request, reads~) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      let identity = match
        @host.prepare_client_cancellation_identity(
          namespace_id,
          @host.client_request_authority_scope_cid(request),
          cancel_id,
          run.definition,
          expected_revision,
        ) {
        Ok(value) => value
        Err(issue) => return Err(CancellationIdentity(issue))
      }
      guard cancellation_index(
          namespace_id,
          @host.client_request_authority_scope_cid(request),
          cancel_id,
        )
        is Some(key) else {
        return Err(Encoding)
      }
      let original = match
        read_client_journal_value(
          self.database,
          "client_cancellations",
          key,
          reads,
        ) {
        Ok(row) =>
          match read_cancellation(row) {
            Ok(value) => Some(value)
            Err(issue) => return Err(issue)
          }
        Err(@sqlite.NotFound) => None
        Err(issue) => return Err(Physical(issue))
      }
      if original is None && run.publication_binding != publication.binding {
        return Err(ChangedIntent)
      }
      // Only a new operation observes the original publication under the same
      // physical journal fence held by the installed Local publication service.
      // The closed observer reads only the scoped durable Store commit.
      let terminal = if original is Some(_) {
        false
      } else {
        match (publication.observe)(run) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      }
      if run.revision > 2147483647L {
        return Err(CapacityExceeded)
      }
      let action = match
        @host.prepare_client_cancellation_operation(
          identity,
          original.map(value => value.identity),
          run.definition,
          run.revision.to_int(),
          true,
          terminal,
          run.cancellation_requested,
        ) {
        Ok(value) => value
        Err(issue) => return Err(CancellationOperation(issue))
      }
      if !current() {
        return Err(AuthorizationDenied)
      }
      match action {
        @host.ReplayOriginalCancellation => Ok(original.unwrap())
        @host.RecordCancellation(action) => {
          if issued >= self.max_records {
            return Err(CapacityExceeded)
          }
          let observed = if action == @host.AcceptCancellation {
            match
              self.save_with_operations(
                { ..run, cancellation_requested: true, },
                operations~,
              ) {
              Ok(value) => value.revision
              Err(issue) => return Err(issue)
            }
          } else {
            run.revision
          }
          let record = {
            namespace_id,
            cancel_id,
            expected_revision,
            request,
            definition: run.definition,
            identity,
            action,
            observed_revision: observed,
          }
          guard cancellation_body(record) is Some(body) else {
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
          // Independently witness exact original result bytes, not only issuance
          // count or a self-consistent intent. Both rows and the request fence
          // commit together; neither lookup nor replay rewrites this witness.
          match
            insert_client_journal_value(
              self.database,
              "client_cancel_originals",
              key,
              @utf8.encode(@journal.effect_response_body_digest(body)),
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
              @utf8.encode((issued + 1).to_string()),
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
      match cancellation_custody(self.database, self.max_records, reads~) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let run = match self.retained(request, reads~) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      let identity = match
        @host.prepare_client_cancellation_identity(
          namespace_id,
          @host.client_request_authority_scope_cid(request),
          cancel_id,
          run.definition,
          expected_revision,
        ) {
        Ok(value) => value
        Err(issue) => return Err(CancellationIdentity(issue))
      }
      guard cancellation_index(
          namespace_id,
          @host.client_request_authority_scope_cid(request),
          cancel_id,
        )
        is Some(key) else {
        return Err(Encoding)
      }
      let original = match
        read_client_journal_value(
          self.database,
          "client_cancellations",
          key,
          reads,
        ) {
        Ok(row) =>
          match read_cancellation(row) {
            Ok(value) => Some(value)
            Err(issue) => return Err(issue)
          }
        Err(@sqlite.NotFound) => None
        Err(issue) => return Err(Physical(issue))
      }
      if !current() {
        return Err(AuthorizationDenied)
      }
      match original {
        None => Ok(UnresolvedCancellationHistory)
        Some(value) =>
          match
            @host.client_cancellation_identity_relation(
              identity,
              value.identity,
            ) {
            @host.SameOperation => Ok(OriginalCancellation(value))
            @host.ChangedIntent =>
              Err(CancellationOperation(@host.ChangedIntent))
            @host.DifferentOperation =>
              Err(CancellationOperation(@host.DifferentOperation))
          }
      }
    },
    reads~,
  )
}
