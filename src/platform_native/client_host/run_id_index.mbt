///|
// A subordinate locator in the existing Journal, never Run authority. The
// referenced original is authenticated again before a selection escapes.
fn run_id_index_key(scope : String, id : String) -> String {
  @sha.hex(@utf8.encode(scope + "\u{0000}" + id))
}

///|
fn NativeClientRunJournal::index_run_id_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  run : NativeClientRunRecord,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.transaction_active ||
    !physical_equal(self.database, authority.database) {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  let scope = @host.client_request_authority_scope_cid(run.request)
  let id = match @publication.run_definition_run_id(run.definition) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let key = run_id_index_key(scope, id)
  let body = @utf8.encode(reference.wire)
  match
    read_client_journal_value(self.database, "client_run_id_index", key, reads) {
    Err(@sqlite.NotFound) =>
      insert_client_journal_value(
        self.database,
        "client_run_id_index",
        key,
        body,
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    Err(issue) => Err(Physical(issue))
    Ok(original) => {
      if original.body == b"ambiguous" {
        return Ok(())
      }
      if original.body == body {
        return Ok(())
      }
      let original_reference = match
        read_run_id_index_reference(original.body) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        self.run_id_original_locked(
          authority,
          original_reference,
          scope,
          id,
          reads~,
        ) {
        Ok(Some(_)) => ()
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      // Preserve the former ambiguous-ID refusal without forbidding a second
      // otherwise valid admission. No ordinary lookup chooses the first row.
      compare_exchange_client_journal_value(
        self.database,
        "client_run_id_index",
        key,
        original.revision,
        b"ambiguous",
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    }
  }
}

///|
fn read_run_id_index_reference(
  body : Bytes,
) -> Result[NativeClientSubmissionReference, NativeClientRunJournalIssue] {
  let wire = @utf8.decode(body) catch { _ => return Err(CustodyLost) }
  @host.admit_client_submission_reference_record(wire)
  .map(native_submission_reference_record)
  .map_err(_ => CustodyLost)
}

///|
fn NativeClientRunJournal::run_id_original_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  scope : String,
  id : String,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[
  (
    NativeClientSubmissionReference,
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
  )?,
  NativeClientRunJournalIssue,
] {
  match
    self.verify_submission_locked(authority, reference, scope, true, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let (submission, selected) = match
    self.retained_submission_with_run(reference, reads~) {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  guard submission.run_admission is Some(admission) && selected is Some(run) else {
    return Ok(None)
  }
  if @host.client_request_authority_scope_cid(admission.request) != scope ||
    !(@publication.run_definition_run_id(run.definition) is Ok(original_id) &&
    original_id == id) {
    return Ok(None)
  }
  Ok(Some((reference, run.request, run.definition)))
}

///|
// The explicit migration supplies only originals admitted in its one bounded
// inventory. The caller owns current RunRead and the same transaction.
fn NativeClientRunJournal::index_admitted_run_ids_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  scope : String,
  issuance : (Int, Int64),
  originals : Array[(NativeClientSubmissionReference, NativeClientRunRecord)],
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.transaction_active ||
    !physical_equal(self.database, authority.database) {
    return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  for (reference, run) in originals {
    if @host.client_request_authority_scope_cid(run.request) != scope {
      continue
    }
    match
      self.verify_submission_locked(authority, reference, scope, true, reads~) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match self.index_run_id_locked(authority, reference, run, operations~) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match
      self.index_saved_run_reference_locked(
        authority,
        reference,
        run,
        operations~,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let body = @utf8.encode(issuance.0.to_string() + ":" + issuance.1.to_string())
  match
    read_client_journal_value(
      self.database,
      "client_run_id_index_coverage",
      scope,
      reads,
    ) {
    Err(@sqlite.NotFound) =>
      insert_client_journal_value(
        self.database,
        "client_run_id_index_coverage",
        scope,
        body,
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    Err(issue) => Err(Physical(issue))
    Ok(original) if original.body == body => Ok(())
    Ok(original) =>
      compare_exchange_client_journal_value(
        self.database,
        "client_run_id_index_coverage",
        scope,
        original.revision,
        body,
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
  }
}

///|
// Missing coverage is not evidence that an arbitrary historical Run is absent.
fn NativeClientRunJournal::run_id_absence_locked(
  self : NativeClientRunJournal,
  scope : String,
  issuance : (Int, Int64),
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[
  (
    NativeClientSubmissionReference,
    @host.ClientRequestIdentity,
    @publication.PublicationContract,
  )?,
  NativeClientRunJournalIssue,
] {
  if issuance.0 == 0 {
    return Ok(None)
  }
  let expected = @utf8.encode(
    issuance.0.to_string() + ":" + issuance.1.to_string(),
  )
  match
    read_client_journal_value(
      self.database,
      "client_run_id_index_coverage",
      scope,
      reads,
    ) {
    Ok(original) if original.body == expected => Ok(None)
    Ok(_) | Err(@sqlite.NotFound) => Err(RunIdIndexIncomplete)
    Err(issue) => Err(Physical(issue))
  }
}

///|
fn NativeClientRunJournal::index_saved_run_reference_locked(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  run : NativeClientRunRecord,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if !self.transaction_active ||
    !physical_equal(self.database, authority.database) {
    return Err(CustodyLost)
  }
  let original = match
    @host.admit_client_submission_reference_record(reference.wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let (key, body) = match
    @host.client_saved_run_reference_locator(
      original,
      run.request,
      run.definition,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let reads = operations.map(value => value.reads)
  match
    read_client_journal_value(
      self.database,
      "client_run_reference_index",
      key,
      reads,
    ) {
    Err(@sqlite.NotFound) =>
      insert_client_journal_value(
        self.database,
        "client_run_reference_index",
        key,
        body,
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    Err(issue) => Err(Physical(issue))
    Ok(existing) => {
      if existing.body == body || existing.body == b"ambiguous" {
        return Ok(())
      }
      let earlier = match read_run_id_index_reference(existing.body) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let id = match @publication.run_definition_run_id(run.definition) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      let (old_reference, old_request, old_definition) = match
        self.run_id_original_locked(
          authority,
          earlier,
          @host.client_request_authority_scope_cid(run.request),
          id,
          reads~,
        ) {
        Ok(Some(value)) => value
        Ok(None) => return Err(CustodyLost)
        Err(issue) => return Err(issue)
      }
      let old_original = match
        @host.admit_client_submission_reference_record(old_reference.wire) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      match
        @host.client_saved_run_reference_locator(
          old_original, old_request, old_definition,
        ) {
        Ok((old_key, old_body)) if old_key == key && old_body == existing.body =>
          ()
        _ => return Err(CustodyLost)
      }
      compare_exchange_client_journal_value(
        self.database,
        "client_run_reference_index",
        key,
        existing.revision,
        b"ambiguous",
        operations,
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    }
  }
}
