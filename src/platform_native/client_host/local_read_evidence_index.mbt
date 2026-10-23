///|
// The exact physical format is observed once in this Journal's existing
// closed operation/snapshot. This DATA does not authorize a read or replace
// the actual Database/Library/current SQL lifetime checked on every use.
fn NativeClientRunJournal::observe_read_evidence_schema(
  self : NativeClientRunJournal,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Int, NativeClientRunJournalIssue] {
  if !self.transaction_active {
    return Err(CustodyLost)
  }
  if reads is Some(access) && !physical_equal(access.database, self.database) {
    return Err(Physical(@sqlite.Collision))
  }
  if self.fenced || client_journal_transaction_fenced(self.database, reads) {
    self.observed_evidence_schema = None
    return Err(Fenced)
  }
  if self.observed_evidence_schema is Some(value) {
    return Ok(value)
  }
  let schema = match client_journal_read_evidence_schema(self.database, reads) {
    Ok(value) if value == 0 || value == 1 => value
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  self.observed_evidence_schema = Some(schema)
  Ok(schema)
}

///|
fn NativeClientRunJournal::require_read_evidence_schema(
  self : NativeClientRunJournal,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  match self.observe_read_evidence_schema(reads~) {
    Ok(1) => Ok(())
    Ok(_) => Err(CustodyLost)
    Err(issue) => Err(issue)
  }
}

///|
// Called only by the existing authorized maintenance transaction. Authenticate
// the bounded original inventory before DDL; a failed audit or install leaves
// the same transaction to roll back, never publishing a process format fact.
fn NativeLocalHostConnection::migrate_read_evidence_schema_locked(
  self : NativeLocalHostConnection,
  max_inspect_rows : Int64,
  operations? : NativeClientJournalOperationAccess? = None,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.journal.transaction_active ||
    max_inspect_rows < 0L ||
    max_inspect_rows > 536870912L {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  match self.journal.observe_read_evidence_schema(reads~) {
    Ok(1) => return Ok(())
    Ok(0) => ()
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  match
    self.read_evidence_custody(
      self.epoch.crypto,
      operations~,
      capture~,
      max_inspect_rows=Some(max_inspect_rows),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.journal.observed_evidence_schema = None
  install_journal_read_evidence_schema(
    self.database,
    max_inspect_rows,
    operations,
  ).map_err(issue => Physical(issue))
}
