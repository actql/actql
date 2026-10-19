///|
pub(all) struct NativeClientResultSelection {
  namespace_id : String
  principal_id : String
  purpose : String
  result_name : String
  format : String
  attempt_id : String
}

///|
pub(all) enum NativeClientSubmittedResultIssue {
  UnresolvedSubmissionHistory
  RunNotAdmitted
  Journal(NativeClientRunJournalIssue)
  ResultAccess(@result_access.NativeResultAccessIssue)
}

///|
/// Resolve only the original durable acceptance. The read has a caller-chosen
/// new attempt; lookup cannot prepare, execute, bind another Run, or retry a
/// previous payload/grant. Read authorization and delivery stay with the
/// existing Result owner. Separate lookups are not an atomic Run snapshot.
pub fn NativeClientRunJournal::open_submitted_result(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  authority_scope_cid : String,
  current : () -> Bool,
  now : Double,
  service : @result_access.NativeResultAccessService,
  selection : NativeClientResultSelection,
) -> Result[
  @result_access.NativeResultAccessSession,
  NativeClientSubmittedResultIssue,
] {
  let admission = match
    self.resolve_submitted_result_binding(
      authority,
      reference,
      authority_scope_cid,
      current,
      now,
      service,
      selection.namespace_id,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @result_access.open_native_result_access(service, {
    namespace_id: selection.namespace_id,
    authority_scope_cid: @host.client_request_authority_scope_cid(
      admission.request,
    ),
    run_definition_cid: admission.run_definition_cid,
    principal_id: selection.principal_id,
    purpose: selection.purpose,
    result_name: selection.result_name,
    format: selection.format,
    attempt_id: selection.attempt_id,
  }).map_err(issue => ResultAccess(issue))
}

///|
/// Shared original-Run/custody resolution for new reads and metadata lookup.
/// Neither caller supplies a replacement Run or adopts current configuration.
fn NativeClientRunJournal::resolve_submitted_result_binding(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  authority_scope_cid : String,
  current : () -> Bool,
  now : Double,
  service : @result_access.NativeResultAccessService,
  namespace_id : String,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[NativeClientSubmittedRunAdmission, NativeClientSubmittedResultIssue] {
  let reads = operations.map(value => value.reads)
  let original = match
    self.lookup_submitted_intent_with_operations(
      authority,
      reference,
      authority_scope_cid,
      current(),
      now,
      operations~,
    ) {
    Ok(Submitted(record)) => record
    Ok(UnresolvedSubmissionHistory) => return Err(UnresolvedSubmissionHistory)
    Err(issue) => return Err(Journal(issue))
  }
  guard original.run_admission is Some(admission) else {
    return Err(RunNotAdmitted)
  }
  let run = match self.lookup_with_reads(admission.request, current(), reads~) {
    Ok(Retained(run)) => run
    Ok(UnresolvedHistory) => return Err(Journal(CustodyLost))
    Err(issue) => return Err(Journal(issue))
  }
  let (store_authority, device, inode) = match service.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(ResultAccess(issue))
  }
  let binding = match
    installed_publication_binding(namespace_id, store_authority, device, inode) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if run.publication_binding != Some(binding) {
    return Err(Journal(ForeignRun))
  }
  if !current() {
    return Err(Journal(AuthorizationDenied))
  }
  Ok(admission)
}

///|
pub(all) struct NativeClientDeliveryAttemptSelection {
  namespace_id : String
  principal_id : String
  purpose : String
  result_name : String
  attempt_id : String
}

///|
/// Observe only the saved original read attempt on the admitted Run. Absence
/// or a missing latest record is not permission to resend/open another attempt.
pub fn NativeClientRunJournal::lookup_submitted_result_delivery(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  authority_scope_cid : String,
  current : () -> Bool,
  now : Double,
  service : @result_access.NativeResultAccessService,
  selection : NativeClientDeliveryAttemptSelection,
) -> Result[
  @publication_store.NativeResultDeliveryLookup?,
  NativeClientSubmittedResultIssue,
] {
  let admission = match
    self.resolve_submitted_result_binding(
      authority,
      reference,
      authority_scope_cid,
      current,
      now,
      service,
      selection.namespace_id,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let observed = @result_access.lookup_native_result_delivery_attempt(service, {
    namespace_id: selection.namespace_id,
    authority_scope_cid: @host.client_request_authority_scope_cid(
      admission.request,
    ),
    run_definition_cid: admission.run_definition_cid,
    principal_id: selection.principal_id,
    purpose: selection.purpose,
    result_name: selection.result_name,
    attempt_id: selection.attempt_id,
  })
  if !current() {
    return Err(Journal(AuthorizationDenied))
  }
  observed.map_err(issue => ResultAccess(issue))
}
