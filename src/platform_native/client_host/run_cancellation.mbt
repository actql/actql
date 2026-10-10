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
) -> Result[(Int, Int64), NativeClientRunJournalIssue] {
  let marker = match database.read("client_cancel_custody", "issued") {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  match database.scan_after("client_cancel_custody", "") {
    Ok(row) if row.key == "issued" => ()
    _ => return Err(CustodyLost)
  }
  match database.scan_after("client_cancel_custody", "issued") {
    Err(@sqlite.NotFound) => ()
    _ => return Err(CustodyLost)
  }
  let text = @utf8.decode(marker.body) catch { _ => return Err(CustodyLost) }
  let count = @string.parse_int(text) catch { _ => return Err(CustodyLost) }
  if count < 0 ||
    count > max_records ||
    count.to_string() != text ||
    marker.revision != count.to_int64() {
    return Err(CustodyLost)
  }
  let mut cursor = ""
  let mut observed = 0
  while true {
    let row = match database.scan_after("client_cancellations", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    observed += 1
    if observed > count {
      return Err(CustodyLost)
    }
    let value = match
      read_cancellation({ body: row.body, revision: row.revision, }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
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
      database.read(
        "client_runs",
        @host.client_request_scope_cid(value.request),
      ) {
      Ok(value) => value
      _ => return Err(CustodyLost)
    }
    let run = match read_run_record(run) {
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
  Ok((count, marker.revision))
}

///|
pub fn NativeClientRunJournal::cancel_operation(
  self : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
  current : () -> Bool,
  terminal_observed : () -> Bool,
) -> Result[NativeClientCancellationRecord, NativeClientRunJournalIssue] {
  if !current() {
    return Err(AuthorizationDenied)
  }
  if self.fenced || self.database.transaction_fenced() {
    return Err(Fenced)
  }
  guard cancellation_index(
      namespace_id,
      @host.client_request_authority_scope_cid(request),
      cancel_id,
    )
    is Some(operation_key) else {
    return Err(Encoding)
  }
  // This index read only avoids unnecessary current-state observation. It is
  // not custody or replay admission; the original transaction below rechecks
  // all issuance, exact key/intent, Run binding and current authority.
  let terminal = match
    self.database.read("client_cancellations", operation_key) {
    Ok(_) => false
    Err(@sqlite.NotFound) => terminal_observed()
    Err(issue) => return Err(Physical(issue))
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => {
    let (issued, witness_revision) = match
      cancellation_custody(self.database, self.max_records) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let run = match self.retained(request) {
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
    let original = match self.database.read("client_cancellations", key) {
      Ok(row) =>
        match read_cancellation(row) {
          Ok(value) => Some(value)
          Err(issue) => return Err(issue)
        }
      Err(@sqlite.NotFound) => None
      Err(issue) => return Err(Physical(issue))
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
          match self.save({ ..run, cancellation_requested: true, }) {
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
        match self.database.insert("client_cancellations", key, body) {
          Ok(_) => ()
          Err(issue) => return Err(Physical(issue))
        }
        match
          self.database.compare_exchange(
            "client_cancel_custody",
            "issued",
            witness_revision,
            @utf8.encode((issued + 1).to_string()),
          ) {
          Ok(_) => Ok(record)
          Err(issue) => Err(Physical(issue))
        }
      }
    }
  })
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
  if !current() {
    return Err(AuthorizationDenied)
  }
  self.transaction(() => {
    match cancellation_custody(self.database, self.max_records) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let run = match self.retained(request) {
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
    let original = match self.database.read("client_cancellations", key) {
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
          @host.client_cancellation_identity_relation(identity, value.identity) {
          @host.SameOperation => Ok(OriginalCancellation(value))
          @host.ChangedIntent => Err(CancellationOperation(@host.ChangedIntent))
          @host.DifferentOperation =>
            Err(CancellationOperation(@host.DifferentOperation))
        }
    }
  })
}
