///|
/// Immutable original-operation custody, not a physical stop or terminal Run.
struct NativeClientCancellationRecord {
  namespace_id : String
  cancel_id : String
  expected_revision : Int
  request : @host.ClientRequestIdentity
  definition : @publication.PublicationContract
  identity : @host.ClientCancellationIdentity
  action : @host.ClientRunCancellationAction
  observed_revision : Int64
}

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
  try {
    let writer = @encode.writer(4096, 4, 1)
    @encode.begin_array(writer)
    for value in [namespace_id, authority, cancel_id] {
      @encode.string_value(writer, value)
    }
    @encode.end_array(writer)
    Some(
      @journal.effect_response_body_digest(@utf8.encode(@encode.finish(writer))),
    )
  } catch {
    _ => None
  }
}

///|
fn cancellation_body(value : NativeClientCancellationRecord) -> Bytes? {
  try {
    let writer = @encode.writer(131072, 32, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "action")
    @encode.string_value(
      writer,
      match value.action {
        @host.AcceptCancellation => "accepted"
        @host.AlreadyRequested => "already_requested"
        @host.AlreadyTerminal => "already_terminal"
      },
    )
    @encode.key(writer, "cancel_id")
    @encode.string_value(writer, value.cancel_id)
    @encode.key(writer, "expected_revision")
    @encode.string_value(writer, value.expected_revision.to_string())
    @encode.key(writer, "intent_cid")
    @encode.string_value(
      writer,
      @host.client_cancellation_intent_cid(value.identity),
    )
    @encode.key(writer, "namespace_id")
    @encode.string_value(writer, value.namespace_id)
    @encode.key(writer, "observed_revision")
    @encode.string_value(writer, value.observed_revision.to_string())
    @encode.key(writer, "request")
    @encode.string_value(
      writer,
      @host.client_request_identity_record_wire(value.request).unwrap(),
    )
    @encode.key(writer, "run_definition")
    @encode.string_value(
      writer,
      @publication.publication_contract_json(value.definition),
    )
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-client-cancellation-row/0.1")
    @encode.end_object(writer)
    Some(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => None
  }
}

///|
fn read_cancellation(
  row : @sqlite.NativeJournalValue,
) -> Result[NativeClientCancellationRecord, NativeClientRunJournalIssue] {
  if row.revision != 0L {
    return Err(CustodyLost)
  }
  let wire = @utf8.decode(row.body) catch { _ => return Err(CustodyLost) }
  guard checkpoint_cursor(wire) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "action", "cancel_id", "expected_revision", "intent_cid", "namespace_id", "observed_revision",
      "request", "run_definition", "version",
    ])
    is Ok(object) &&
    epoch_text(object, "version") ==
    Some("actql-native-client-cancellation-row/0.1") &&
    epoch_text(object, "namespace_id") is Some(namespace_id) &&
    epoch_text(object, "cancel_id") is Some(cancel_id) &&
    epoch_text(object, "request") is Some(request_wire) &&
    epoch_text(object, "run_definition") is Some(definition_wire) &&
    @decode.lookup(object, "expected_revision") is Some(expected) &&
    @decode.decimal_int64(expected) is Ok(expected) &&
    expected >= 0L &&
    expected <= 2147483647L &&
    @decode.lookup(object, "observed_revision") is Some(observed) &&
    @decode.decimal_int64(observed) is Ok(observed) &&
    observed >= 0L else {
    return Err(CustodyLost)
  }
  let request = match
    @host.admit_client_request_identity_record_wire(request_wire) {
    Ok(value) => value
    _ => return Err(CustodyLost)
  }
  let definition = match
    @publication.admit_publication_contract(
      "run_definition", definition_wire, 65536, 4096, 64,
    ) {
    Ok(value) => value
    _ => return Err(CustodyLost)
  }
  let identity = match
    @host.prepare_client_cancellation_identity(
      namespace_id,
      @host.client_request_authority_scope_cid(request),
      cancel_id,
      definition,
      expected.to_int(),
    ) {
    Ok(value) => value
    _ => return Err(CustodyLost)
  }
  let action = match epoch_text(object, "action") {
    Some("accepted") => @host.AcceptCancellation
    Some("already_requested") => @host.AlreadyRequested
    Some("already_terminal") => @host.AlreadyTerminal
    _ => return Err(CustodyLost)
  }
  if epoch_text(object, "intent_cid") !=
    Some(@host.client_cancellation_intent_cid(identity)) ||
    observed !=
    expected + (if action == @host.AcceptCancellation { 1L } else { 0L }) {
    return Err(CustodyLost)
  }
  let value = {
    namespace_id,
    cancel_id,
    expected_revision: expected.to_int(),
    request,
    definition,
    identity,
    action,
    observed_revision: observed,
  }
  guard cancellation_body(value) == Some(row.body) else {
    return Err(CustodyLost)
  }
  Ok(value)
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
  let marker = match
    read_client_journal_value(
      database, "client_cancel_custody", "issued", reads,
    ) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  match
    scan_client_journal_value(database, "client_cancel_custody", "", reads) {
    Ok(row) if row.key == "issued" => ()
    _ => return Err(CustodyLost)
  }
  match
    scan_client_journal_value(
      database, "client_cancel_custody", "issued", reads,
    ) {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  let count = match
    @host.client_journal_issuance_count(marker.body, max_records) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if marker.revision != count.to_int64() {
    return Err(CustodyLost)
  }
  let mut cursor = ""
  let mut observed = 0
  while true {
    let row = match
      scan_client_journal_value(database, "client_cancellations", cursor, reads) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    if observed >= count {
      return Err(CustodyLost)
    }
    observed += 1
    let value = match
      read_cancellation({ body: row.body, revision: row.revision, }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let original = match
      read_client_journal_value(
        database,
        "client_cancel_originals",
        row.key,
        reads,
      ) {
      Ok(value) => value
      _ => return Err(CustodyLost)
    }
    if original.revision != 0L ||
      original.body !=
      @utf8.encode(@journal.effect_response_body_digest(row.body)) {
      return Err(CustodyLost)
    }
    if cancellation_index(
        value.namespace_id,
        @host.client_request_authority_scope_cid(value.request),
        value.cancel_id,
      ) !=
      Some(row.key) {
      return Err(CustodyLost)
    }
    let run = match
      read_client_journal_value(
        database,
        "client_runs",
        @host.client_request_scope_cid(value.request),
        reads,
      ) {
      Ok(value) => value
      _ => return Err(CustodyLost)
    }
    let run = match
      read_run_record(
        run,
        before_construction=run_decode_construction(database, reads),
        before_metadata_construction=run_metadata_construction(database, reads),
      ) {
      Ok(value) => value
      _ => return Err(CustodyLost)
    }
    if @host.client_request_identity_relation(value.request, run.request) !=
      @host.SameRequest ||
      @publication.publication_contract_identity(value.definition) !=
      @publication.publication_contract_identity(run.definition) ||
      run.revision < value.observed_revision ||
      (value.action != @host.AlreadyTerminal && !run.cancellation_requested) {
      return Err(CustodyLost)
    }
    cursor = row.key
  }
  if observed != count {
    return Err(CustodyLost)
  }
  let mut original_cursor = ""
  let mut originals = 0
  while true {
    let row = match
      scan_client_journal_value(
        database, "client_cancel_originals", original_cursor, reads,
      ) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    if originals >= count || row.revision != 0L {
      return Err(CustodyLost)
    }
    originals += 1
    match
      read_client_journal_value(
        database,
        "client_cancellations",
        row.key,
        reads,
      ) {
      Ok(_) => ()
      _ => return Err(CustodyLost)
    }
    original_cursor = row.key
  }
  if originals != count {
    return Err(CustodyLost)
  }
  Ok((count, marker.revision))
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
