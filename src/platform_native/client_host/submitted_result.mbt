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
  let original = match
    self.lookup_submitted_intent(
      authority,
      reference,
      authority_scope_cid,
      current(),
      now,
    ) {
    Ok(Submitted(record)) => record
    Ok(UnresolvedSubmissionHistory) => return Err(UnresolvedSubmissionHistory)
    Err(issue) => return Err(Journal(issue))
  }
  guard original.run_admission is Some(admission) else {
    return Err(RunNotAdmitted)
  }
  let run = match self.lookup(admission.request, current()) {
    Ok(Retained(run)) => run
    Ok(UnresolvedHistory) => return Err(Journal(CustodyLost))
    Err(issue) => return Err(Journal(issue))
  }
  let (store_authority, device, inode) = match service.custody_location() {
    Ok(value) => value
    Err(issue) => return Err(ResultAccess(issue))
  }
  let binding = match
    installed_publication_binding(
      selection.namespace_id,
      store_authority,
      device,
      inode,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if run.publication_binding != Some(binding) {
    return Err(Journal(ForeignRun))
  }
  if !current() {
    return Err(Journal(AuthorizationDenied))
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
