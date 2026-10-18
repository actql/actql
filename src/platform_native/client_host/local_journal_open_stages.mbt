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
// The original commit may have succeeded. Inspect, never rerun bootstrap.
fn NativeLocalAdoptionSession::inspect_retained_journal(
  self : NativeLocalAdoptionSession,
  library : @sqlite.Library,
  max_snapshot_bytes : Int64,
  max_records : Int,
) -> Result[Bool, NativeLocalAdoptionIssue] {
  match
    inspect_native_client_state(
      library,
      self.state_path + "/client.sqlite3",
      131072L,
      max_snapshot_bytes,
      max_records,
    ) {
    Ok(Retained) => Ok(false)
    Ok(PhysicallyAbsent) => Err(CustodyLost)
    Err(issue) => Err(Inspection(issue))
  }
}

///|
// Physical SQLite stage. Keep the complete Run/Policy/Effect custody
// transaction and name-startup audit in their original order.
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
  match local_adoption_row(database, adoption_body, reads~) {
    Ok(_) => ()
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
    open_native_client_run_journal_with_reads(database, max_records, reads~) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  match journal.submitted_intent_custody(reads~) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  // Keep the inherited Run/Policy custody transaction. Only the new name
  // extension's full census/HMAC scan belongs here at startup, not each lookup.
  match
    journal.transaction_with_reads(
      () => journal.inspect_submitted_name_startup(epoch, reads~),
      reads~,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  Ok((epoch, journal))
}
