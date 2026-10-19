///|
// Subordinate locator in the same Journal. Neither this key nor its DATA body
// authenticates an epoch, grants RunRead or supplies approval/continuation.
fn checkpoint_id_index_key(scope : String, id : String) -> String {
  @sha.hex(@utf8.encode(scope + "\u{0000}" + id))
}

///|
fn checkpoint_id_index_body(
  request : @host.ClientRequestIdentity,
  checkpoint : @checkpoint.SealedCheckpoint,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  let request_wire = match @host.client_request_identity_record_wire(request) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  try {
    let writer = @encode.writer(262144, 16, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "checkpoint_cid")
    @encode.string_value(writer, checkpoint.checkpoint_cid)
    @encode.key(writer, "checkpoint_id")
    @encode.string_value(writer, checkpoint.checkpoint.checkpoint_id)
    @encode.key(writer, "request")
    @encode.string_value(writer, request_wire)
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn read_checkpoint_id_index(
  body : Bytes,
) -> Result[
  (@host.ClientRequestIdentity, String, String),
  NativeClientRunJournalIssue,
] {
  let text = @utf8.decode(body) catch { _ => return Err(CustodyLost) }
  guard checkpoint_cursor(text) is Some(cursor) &&
    @decode.closed_object(cursor, ["checkpoint_cid", "checkpoint_id", "request"])
    is Ok(object) else {
    return Err(CustodyLost)
  }
  let field = name => {
    @decode.lookup(object, name).bind(value => @decode.text(value).to_option())
  }
  guard field("request") is Some(wire) &&
    @host.admit_client_request_identity_record_wire(wire) is Ok(request) &&
    field("checkpoint_id") is Some(id) &&
    field("checkpoint_cid") is Some(cid) else {
    return Err(CustodyLost)
  }
  Ok((request, id, cid))
}

///|
// Called only after the Run CAS inside its existing transaction. Replacement
// removes the prior locator in that same transaction, so retained index size
// does not grow with historical checkpoints. Legacy missing entries never
// backfill when an unchanged checkpoint is merely observed or updated.
fn NativeClientRunJournal::save_checkpoint_id_index(
  self : NativeClientRunJournal,
  before : NativeClientRunRecord,
  after : NativeClientRunRecord,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.transaction_active {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  let scope = @host.client_request_authority_scope_cid(after.request)
  let previous = before.checkpoint.map(value => value.artifact)
  let next = after.checkpoint.map(value => value.artifact)
  if previous == next {
    return Ok(())
  }
  if previous is Some(original) {
    let key = checkpoint_id_index_key(scope, original.checkpoint.checkpoint_id)
    match
      read_client_journal_value(
        self.database,
        "client_checkpoint_id_index",
        key,
        reads,
      ) {
      Err(@sqlite.NotFound) => ()
      Err(issue) => return Err(Physical(issue))
      Ok(row) => {
        let expected = match
          checkpoint_id_index_body(before.request, original) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if row.revision != 0L || row.body != expected {
          return Err(CustodyLost)
        }
        match
          remove_exact_client_journal_value(
            self.database,
            "client_checkpoint_id_index",
            key,
            row.revision,
            row.body,
            operations,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Physical(issue))
        }
      }
    }
  }
  if next is Some(original) {
    let key = checkpoint_id_index_key(scope, original.checkpoint.checkpoint_id)
    let body = match checkpoint_id_index_body(after.request, original) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    // A live same-scope ID cannot silently select another original Run.
    match
      read_client_journal_value(
        self.database,
        "client_checkpoint_id_index",
        key,
        reads,
      ) {
      Err(@sqlite.NotFound) => ()
      Err(issue) => return Err(Physical(issue))
      Ok(_) => return Err(CustodyLost)
    }
    match
      insert_client_journal_value(
        self.database,
        "client_checkpoint_id_index",
        key,
        body,
        operations,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok(())
}

///|
// Exact locator read followed by the complete original Run row validator.
// The inherited transaction custody checks remain unchanged; no claim is made
// that all Journal work is scan-free. This operation never searches unknown IDs.
fn NativeClientRunJournal::checkpoint_request_by_id_locked(
  self : NativeClientRunJournal,
  scope : String,
  id : String,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[@host.ClientRequestIdentity?, NativeClientRunJournalIssue] {
  if !self.transaction_active {
    return Err(CustodyLost)
  }
  let row = match
    read_client_journal_value(
      self.database,
      "client_checkpoint_id_index",
      checkpoint_id_index_key(scope, id),
      reads,
    ) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Ok(None)
    Err(issue) => return Err(Physical(issue))
  }
  if row.revision != 0L {
    return Err(CustodyLost)
  }
  let (request, retained_id, cid) = match read_checkpoint_id_index(row.body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if retained_id != id ||
    @host.client_request_authority_scope_cid(request) != scope {
    return Err(CustodyLost)
  }
  let record = match self.retained(request, reads~) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  guard record.checkpoint is Some(checkpoint) &&
    checkpoint.artifact.checkpoint.checkpoint_id == id &&
    checkpoint.artifact.checkpoint_cid == cid &&
    checkpoint_id_index_body(record.request, checkpoint.artifact) is Ok(body) &&
    body == row.body else {
    return Err(CustodyLost)
  }
  Ok(Some(record.request))
}
