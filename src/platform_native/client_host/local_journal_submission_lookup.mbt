///|
/// Observe only original Submission custody under the same captured Read.
/// Missing history grants neither nonacceptance proof nor another submission.
pub fn NativeLocalJournalCapture::lookup_submitted_intent_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
  reference : NativeClientSubmissionReference,
  now : Double,
) -> Result[NativeClientSubmittedIntentLookup, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(true) => ()
      Ok(false) => return Err(Journal(AuthorizationDenied))
      Err(issue) => return Err(issue)
    }
    let observed = match
      host.journal.lookup_submitted_intent_with_operations(
        host.epoch,
        reference,
        expected_scope,
        true,
        now,
        operations=Some(operations),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    // The durable clock and Journal transaction may change current originals.
    match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(true) => Ok(observed)
      Ok(false) => Err(Journal(AuthorizationDenied))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Preserve the exact already-checked row selected by original request ID.
/// The selector independently checks RunRead; the reply still requires Submit.
/// Do not discard the row and repeat its clock, selection or full admission.
pub fn NativeLocalJournalCapture::lookup_submitted_intent_by_request_id_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
  request_id : String,
  now : Double,
) -> Result[NativeClientSubmittedIntentLookup?, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(true) => ()
      Ok(false) => return Err(Journal(AuthorizationDenied))
      Err(issue) => return Err(issue)
    }
    let selected = match
      host.lookup_submitted_record_by_request_id_with_operations(
        self.crypto,
        principal,
        connection,
        request_id,
        now,
        operations=Some(operations),
        capture=Some(self),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(true) => Ok(selected.map(record => Submitted(record)))
      Ok(false) => Err(Journal(AuthorizationDenied))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Resolve the same retained Run after its original Submission was admitted.
/// The existing Journal reuses only its unchanged selected row; no current
/// Program, compilation, new Run or caller Boolean supplies that binding.
pub fn NativeLocalJournalCapture::lookup_submitted_run_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
  admission : NativeClientSubmittedRunAdmission,
) -> Result[NativeClientRunRecord, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(true) => ()
      Ok(false) => return Err(Journal(AuthorizationDenied))
      Err(issue) => return Err(issue)
    }
    let run = match
      host.journal.lookup_submitted_admission_with_reads(
        admission,
        expected_scope,
        reads=Some(operations.reads),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    match
      self.original_submit_allowed(
        host, material, principal, connection, expected_scope,
      ) {
      Ok(true) => Ok(run)
      Ok(false) => Err(Journal(AuthorizationDenied))
      Err(issue) => Err(issue)
    }
  })
}

///|
// One original Submission-to-Run join, shared by current Submit and Cancel
// callers. Permission is checked independently by each captured operation.
fn NativeClientRunJournal::lookup_submitted_admission_with_reads(
  self : NativeClientRunJournal,
  admission : NativeClientSubmittedRunAdmission,
  expected_scope : String,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[NativeClientRunRecord, NativeClientRunJournalIssue] {
  if @host.client_request_authority_scope_cid(admission.request) !=
    expected_scope {
    return Err(ChangedIntent)
  }
  let run = match self.lookup_with_reads(admission.request, true, reads~) {
    Ok(Retained(value)) => value
    Ok(UnresolvedHistory) => return Err(CustodyLost)
    Err(issue) => return Err(issue)
  }
  if @publication.publication_contract_identity(run.definition) !=
    admission.run_definition_cid {
    return Err(CustodyLost)
  }
  Ok(run)
}
