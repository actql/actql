///|
// Physical Read stage only. The marker and original body select whether the
// following SQLite stage must inspect retained state; this Bool issues nothing.
fn NativeLocalAdoptionSession::prepare_journal_marker(
  self : NativeLocalAdoptionSession,
  ownership : @filesystem.NativeFileOwnership,
  adoption_body : Bytes,
) -> Result[Bool, NativeLocalAdoptionIssue] {
  let marker = match self.root.inspect_generation("journal-initializing.json") {
    Ok(value) => value
    Err(issue) => return Err(Filesystem(issue))
  }
  let first = match marker {
    None if self.existing_only => return Err(CustodyLost)
    None => {
      guard self.root.inspect_generation("client.sqlite3") is Ok(Some(file)) &&
        file.device == ownership.device &&
        file.inode == ownership.inode &&
        file.size == 0L else {
        return Err(CustodyLost)
      }
      match
        local_adoption_write(
          self.root,
          "journal-initializing.json",
          adoption_body,
        ) {
        Ok(_) => true
        Err(issue) => return Err(issue)
      }
    }
    Some(_) => {
      let (body, _) = match
        local_adoption_read(self.root, "journal-initializing.json", 8192L) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if body != adoption_body {
        return Err(CustodyLost)
      }
      false
    }
  }
  Ok(first)
}

///|
// Ordinary open validates installation and issuance anchors. Target operations
// admit their own originals; whole-history audits are explicit operations.
fn NativeLocalAdoptionSession::bind_journal_sqlite_originals(
  self : NativeLocalAdoptionSession,
  database : @sqlite.Database,
  crypto : @crypto.Library,
  adoption_body : Bytes,
  first : Bool,
  initial : NativeLocalInitialSigningCapture?,
  ttl_ms : Double,
  max_records : Int,
  reads? : NativeClientJournalReadAccess? = None,
  bootstrap? : NativeClientJournalBootstrapAccess? = None,
  opening_ownership? : @filesystem.NativeFileOwnership? = None,
  max_retained_intent_bytes? : Int64 = 67108864L,
) -> Result[
  (NativeClientEpochAuthority, NativeClientRunJournal),
  NativeLocalAdoptionIssue,
] {
  if first {
    // A scoped initializer must use the exact same private SQL routing view
    // for its first writes and the following retained-original audit.
    if reads is Some(original_reads) {
      guard bootstrap is Some(original_bootstrap) &&
        physical_equal(original_reads, original_bootstrap.reads) else {
        return Err(InvalidInput)
      }
    } else if bootstrap is Some(_) {
      return Err(InvalidInput)
    }
    match
      initialize_native_local_client_custody(
        database,
        crypto,
        adoption_body,
        settings=Some(self.settings),
        initial_signing=initial,
        bootstrap~,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let adoption = match
    local_adoption_original_row(database, adoption_body, reads~) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let epoch = match
    open_native_client_epoch_authority_with_reads(
      database,
      crypto,
      ttl_ms,
      reads~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Epoch(issue))
  }
  let journal = match
    open_native_client_run_journal_with_reads(
      database,
      max_records,
      reads~,
      max_retained_intent_bytes~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  match
    client_journal_issuance_anchor(
      database,
      "client_submitted_intent_custody",
      max_records,
      reads~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  match journal.inspect_submitted_name_control(epoch, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  if opening_ownership is Some(ownership) {
    // This is captured DATA from the actual opening, not an Allow. Only a
    // command that opened inside its own read entry retains it; a later public
    // read entry clears it before observing current state again.
    journal.admitted_adoption = Some(
      @host.Observed(
        database,
        self.configuration,
        self.source_body,
        { key: adoption.key, body: adoption.body, revision: adoption.revision, },
        (ownership.device, ownership.inode),
      ),
    )
  }
  Ok((epoch, journal))
}
