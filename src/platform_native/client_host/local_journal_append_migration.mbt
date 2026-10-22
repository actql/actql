///|
// The actual SQLite schema distinguishes the legacy format from adopted
// metadata loss. Its UNIQUE constraint is part of the original row mutation;
// no record-level locator supplies a second definition authority.
fn NativeClientRunJournal::migrate_append_metadata_locked(
  self : NativeClientRunJournal,
  max_inspect_rows : Int64,
  authority : NativeClientEpochAuthority,
  scope : String,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.transaction_active ||
    max_inspect_rows < 1L ||
    max_inspect_rows > 536870912L ||
    !physical_equal(self.database, authority.database) {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  if self.append_schema == 1 {
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
    match
      @host.client_submitted_journal_usage(usage, submitted.0, self.max_records) {
      Ok(_) => ()
      Err(_) => return Err(CustodyLost)
    }
    // A complete scope-local locator needs no second inventory on repeated
    // maintenance. Missing coverage is not interpreted as target absence.
    match self.run_id_absence_locked(scope, submitted, reads~) {
      Ok(_) => return Ok(())
      Err(RunIdIndexIncomplete) => ()
      Err(issue) => return Err(issue)
    }
    let (_, issuance, originals) = match
      self.collect_legacy_append_usage_locked(operations~) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    return self.index_admitted_run_ids_locked(
      authority,
      scope,
      issuance,
      originals,
      operations~,
    )
  }
  if self.append_schema != 0 {
    return Err(CustodyLost)
  }
  // Only a legacy schema with no partial usage metadata can be migrated.
  match
    scan_client_journal_value(
      self.database,
      "client_submitted_intent_usage",
      "",
      reads,
    ) {
    Err(@sqlite.NotFound) => ()
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  let (usage, issuance, originals) = match
    self.collect_legacy_append_usage_locked(operations~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    install_journal_run_definition_schema(
      self.database,
      max_inspect_rows,
      operations,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  match
    insert_client_journal_value(
      self.database,
      "client_submitted_intent_usage",
      "retained",
      usage,
      operations,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Physical(issue))
  }
  self.index_admitted_run_ids_locked(
    authority,
    scope,
    issuance,
    originals,
    operations~,
  )
}

///|
/// Explicit maintenance under this Host's actual current RunRead. The row-work
/// bound is the existing inspection bound, not capacity or permission credit.
/// No original is renewed, repaired, sent, or executed.
pub fn NativeLocalHostConnection::migrate_journal_append_metadata(
  self : NativeLocalHostConnection,
  principal : String,
  connection : String,
  max_inspect_rows : Int64,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let material = match self.adopted_current_material() {
    Ok(value) => value
    Err(_) => return Err(AuthorizationDenied)
  }
  guard @host.client_local_adopted_account_outcome(material, self.database, {
      principal,
      connection,
      resource: "run",
      operation: "read",
    })
    is Ok(Allow(_)) else {
    return Err(AuthorizationDenied)
  }
  let body = match
    @host.client_local_adopted_authority_scope_body(
      material,
      self.database,
      principal,
      connection,
    ) {
    Ok(value) => value
    Err(_) => return Err(AuthorizationDenied)
  }
  let scope = match local_adoption_digest(self.epoch.crypto, body) {
    Ok(value) => value
    Err(_) => return Err(AuthorizationDenied)
  }
  let result = self.journal.transaction(() => {
    match
      self.journal.migrate_append_metadata_locked(
        max_inspect_rows,
        self.epoch,
        scope,
      ) {
      Ok(_) => self.migrate_read_evidence_schema_locked(max_inspect_rows)
      Err(issue) => Err(issue)
    }
  })
  if result is Ok(_) {
    // Only the actual original COMMIT ACK publishes the new format fact.
    self.journal.append_schema = 1
    self.journal.observed_evidence_schema = Some(1)
  }
  result
}

///|
/// Inner Journal/Unknown and outer physical-return failures retain their
/// independent originals. A failed COMMIT cannot install a cached format.
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
    let scope = match
      self.operation_scope(host, material, principal, connection) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let result = host.journal.transaction_with_reads(
      () => {
        match
          host.journal.migrate_append_metadata_locked(
            self.max_snapshot_bytes,
            host.epoch,
            scope,
            operations=Some(operations),
          ) {
          Ok(_) =>
            host.migrate_read_evidence_schema_locked(
              self.max_snapshot_bytes,
              operations=Some(operations),
              capture=Some(self),
            )
          Err(issue) => Err(issue)
        }
      },
      reads=Some(operations.reads),
    )
    if result is Ok(_) {
      host.journal.append_schema = 1
      host.journal.observed_evidence_schema = Some(1)
    }
    Ok(result)
  })
}
