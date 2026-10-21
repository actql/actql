///|
// Format installation uses the existing bounded SQLite claim original. The
// records API cannot remove that claim when an indexed record is deleted.
// It supplies no permission, epoch, execution claim, or new Journal.
fn NativeClientRunJournal::migrate_append_metadata_locked(
  self : NativeClientRunJournal,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.transaction_active {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  match lookup_journal_append_format(self.database, operations) {
    Err(issue) => return Err(Physical(issue))
    Ok(Some(1L)) => {
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
      match self.run_append_coverage_locked(issuance, reads) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let submitted = match
        client_journal_issuance_anchor(
          self.database,
          "client_submitted_intent_custody",
          self.max_records,
          reads~,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let usage = match
        client_journal_read(
          self.database,
          "client_submitted_intent_usage",
          "retained",
          reads~,
        ) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      @host.client_submitted_journal_usage(usage, submitted.0, self.max_records)
      .map(_ => ())
      .map_err(_ => CustodyLost)
    }
    Ok(Some(_)) => Err(CustodyLost)
    Ok(None) => {
      // Only the old, unindexed format can enter this explicit migration.
      // Partial/new metadata without its installation original is not legacy.
      for
        table in [
          "client_run_append_coverage", "client_run_definition_index", "client_submitted_intent_usage",
        ] {
        match scan_client_journal_value(self.database, table, "", reads) {
          Err(@sqlite.NotFound) => ()
          Ok(_) => return Err(CustodyLost)
          Err(issue) => return Err(Physical(issue))
        }
      }
      match self.index_legacy_append_metadata_locked(operations~) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      match claim_journal_append_format(self.database, operations) {
        Ok(@sqlite.Fresh(1L)) => Ok(())
        Ok(_) => Err(CustodyLost)
        Err(issue) => Err(Physical(issue))
      }
    }
  }
}

///|
/// Explicit maintenance under this Host's actual current RunRead. No original
/// is renewed, repaired, sent, or executed. Ordinary open/read never selects it.
pub fn NativeLocalHostConnection::migrate_journal_append_metadata(
  self : NativeLocalHostConnection,
  principal : String,
  connection : String,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard self.authorize({
      principal,
      connection,
      resource: "run",
      operation: "read",
    })
    is Ok(Allow(_)) else {
    return Err(AuthorizationDenied)
  }
  self.journal.transaction(() => self.journal.migrate_append_metadata_locked())
}

///|
/// The selected CLI maintenance consumes this capture's current Account and
/// original Read/SQL ports. Inner Journal/Unknown and outer physical-return
/// failures retain their existing independent Owners.
pub fn NativeLocalJournalCapture::migrate_journal_append_metadata_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
) -> Result[Result[Unit, NativeClientRunJournalIssue], NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    let allowed = match
      self.operation_account(host, material, {
        principal,
        connection,
        resource: "run",
        operation: "read",
      }) {
      Ok(Allow(_)) => true
      Ok(_) => false
      Err(issue) => return Err(issue)
    }
    if !allowed {
      return Ok(Err(AuthorizationDenied))
    }
    Ok(
      host.journal.transaction_with_reads(
        () => {
          host.journal.migrate_append_metadata_locked(
            operations=Some(operations),
          )
        },
        reads=Some(operations.reads),
      ),
    )
  })
}
