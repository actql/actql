///|
/// Select the original signed Submission and its admitted Run under current
/// Cancel authority. Neither a supplied Run reference nor its CID grants use.
pub fn NativeLocalJournalCapture::lookup_submitted_run_for_cancellation_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
  reference : NativeClientSubmissionReference,
  now : Double,
) -> Result[
  (NativeClientSubmittedRunAdmission, NativeClientRunRecord),
  NativeLocalAdoptionIssue,
] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    match
      self.original_run_operation_allowed(
        host, material, principal, connection, expected_scope, "cancel",
      ) {
      Ok(true) => ()
      Ok(false) => return Err(Journal(AuthorizationDenied))
      Err(issue) => return Err(issue)
    }
    let admission = match
      host.journal.lookup_submitted_intent_with_operations(
        host.epoch,
        reference,
        expected_scope,
        true,
        now,
        operations=Some(operations),
      ) {
      Ok(Submitted(record)) =>
        match record.run_admission {
          Some(value) => value
          None => return Err(Journal(CustodyLost))
        }
      Ok(UnresolvedSubmissionHistory) => return Err(Journal(CustodyLost))
      Err(issue) => return Err(Journal(issue))
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
      self.original_run_operation_allowed(
        host, material, principal, connection, expected_scope, "cancel",
      ) {
      Ok(true) => Ok((admission, run))
      Ok(false) => Err(Journal(AuthorizationDenied))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Observe only the same immutable cancellation record. It performs no Store
/// action, stop, retry, revision refresh or new execution admission.
pub fn NativeLocalJournalCapture::lookup_cancellation_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
  request : @host.ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
) -> Result[NativeClientCancellationLookup, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    if @host.client_request_authority_scope_cid(request) != expected_scope {
      return Err(Journal(ChangedIntent))
    }
    let failure : Ref[NativeLocalAdoptionIssue?] = Ref(None)
    let current = () => {
      match
        self.original_run_operation_allowed(
          host, material, principal, connection, expected_scope, "cancel",
        ) {
        Ok(value) => value
        Err(issue) => {
          if failure.val is None {
            failure.val = Some(issue)
          }
          false
        }
      }
    }
    let result = host.journal.lookup_cancellation_with_reads(
      request,
      namespace_id,
      cancel_id,
      expected_revision,
      current,
      reads=Some(operations.reads),
    )
    match failure.val {
      Some(issue) => Err(issue)
      None => result.map_err(issue => Journal(issue))
    }
  })
}

///|
/// Record through the same Journal transaction and original Store observer.
/// This retains the existing cancellation Owner, immutable intent, current
/// fences and lost-COMMIT uncertainty. A record is never physical stop ACK.
pub fn NativeLocalJournalCapture::cancel_operation_in_original_read(
  self : NativeLocalJournalCapture,
  principal : String,
  connection : String,
  expected_scope : String,
  request : @host.ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
  publication : NativeClientCancellationPublication,
) -> Result[NativeClientCancellationRecord, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    material,
    operations,
  ) => {
    if @host.client_request_authority_scope_cid(request) != expected_scope {
      return Err(Journal(ChangedIntent))
    }
    let failure : Ref[NativeLocalAdoptionIssue?] = Ref(None)
    let current = () => {
      match
        self.original_run_operation_allowed(
          host, material, principal, connection, expected_scope, "cancel",
        ) {
        Ok(value) => value
        Err(issue) => {
          if failure.val is None {
            failure.val = Some(issue)
          }
          false
        }
      }
    }
    let result = host.journal.cancel_operation_with_operations(
      request,
      namespace_id,
      cancel_id,
      expected_revision,
      current,
      publication,
      operations=Some(operations),
    )
    match failure.val {
      Some(issue) => Err(issue)
      None => result.map_err(issue => Journal(issue))
    }
  })
}
