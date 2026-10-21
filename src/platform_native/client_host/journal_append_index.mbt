///|
// The coverage body is tied to this Journal's monotonic issuance coordinate.
// Missing compatibility coverage is not absence or permission to create a Run.
fn journal_append_coverage(count : Int, revision : Int64) -> Bytes {
  @utf8.encode(count.to_string() + ":" + revision.to_string())
}

///|
fn NativeClientRunJournal::run_append_coverage_locked(
  self : NativeClientRunJournal,
  issuance : (Int, Int64),
  reads : NativeClientJournalReadAccess?,
) -> Result[@sqlite.NativeJournalValue, NativeClientRunJournalIssue] {
  match read_client_journal_value(
    self.database, "client_run_append_coverage", "issued", reads,
  ) {
    Ok(row) if row.body == journal_append_coverage(issuance.0, issuance.1) => Ok(row)
    Ok(_) | Err(@sqlite.NotFound) => Err(CustodyLost)
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn NativeClientRunJournal::check_run_definition_available_locked(
  self : NativeClientRunJournal,
  definition : @publication.PublicationContract,
  reads : NativeClientJournalReadAccess?,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let cid = @publication.publication_contract_identity(definition)
  let locator = match read_client_journal_value(
    self.database, "client_run_definition_index", cid, reads,
  ) {
    Err(@sqlite.NotFound) => return Ok(())
    Err(issue) => return Err(Physical(issue))
    Ok(value) => value
  }
  let key = @utf8.decode(locator.body) catch { _ => return Err(CustodyLost) }
  let row = match read_client_journal_value(self.database, "client_runs", key, reads) {
    Ok(value) => value
    Err(@sqlite.NotFound) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  let run = match read_run_record(row) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if key != @host.client_request_scope_cid(run.request) ||
    @publication.publication_contract_identity(run.definition) != cid {
    return Err(CustodyLost)
  }
  Err(ForeignRun)
}

///|
// This runs only through explicit bounded compatibility indexing, never open
// or ordinary append. Existing originals and their full custody establish the
// index; a missing or inconsistent original cannot be replaced or executed.
fn NativeClientRunJournal::index_legacy_append_metadata_locked(
  self : NativeClientRunJournal,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.transaction_active {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  let issuance = match run_journal_custody(self.database, self.max_records, reads~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut cursor = ""
  let mut count = 0
  while true {
    let row = match scan_client_journal_value(self.database, "client_runs", cursor, reads) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    count += 1
    if count > issuance.0 || row.key <= cursor {
      return Err(CustodyLost)
    }
    cursor = row.key
    let run = match read_run_record({ body: row.body, revision: row.revision, }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let cid = @publication.publication_contract_identity(run.definition)
    let body = @utf8.encode(row.key)
    match read_client_journal_value(self.database, "client_run_definition_index", cid, reads) {
      Ok(value) if value.body == body => ()
      Ok(_) => return Err(CustodyLost)
      Err(@sqlite.NotFound) => {
        match insert_client_journal_value(
          self.database, "client_run_definition_index", cid, body, operations,
        ) {
          Ok(_) => ()
          Err(issue) => return Err(Physical(issue))
        }
      }
      Err(issue) => return Err(Physical(issue))
    }
  }
  if count != issuance.0 {
    return Err(CustodyLost)
  }
  let body = journal_append_coverage(issuance.0, issuance.1)
  match read_client_journal_value(self.database, "client_run_append_coverage", "issued", reads) {
    Ok(row) => {
      match compare_exchange_client_journal_value(
        self.database, "client_run_append_coverage", "issued", row.revision, body, operations,
      ) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
    }
    Err(@sqlite.NotFound) => {
      match insert_client_journal_value(
        self.database, "client_run_append_coverage", "issued", body, operations,
      ) {
        Ok(_) => ()
        Err(issue) => return Err(Physical(issue))
      }
    }
    Err(issue) => return Err(Physical(issue))
  }
  let (count, bytes, _) = match self.submitted_intent_custody(reads~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let body = match @host.client_submitted_journal_usage_body(count, bytes, self.max_records) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  match read_client_journal_value(self.database, "client_submitted_intent_usage", "retained", reads) {
    Ok(row) if row.body == body => Ok(())
    Ok(_) => Err(CustodyLost)
    Err(@sqlite.NotFound) => insert_client_journal_value(
      self.database, "client_submitted_intent_usage", "retained", body, operations,
    ).map(_ => ()).map_err(issue => Physical(issue))
    Err(issue) => Err(Physical(issue))
  }
}
