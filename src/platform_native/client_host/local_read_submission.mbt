///|
/// Resolve only the exact original Submission/Run and actual service Store
/// under this binding's current independent Run/named-Result read authority.
/// This returns retained admission DATA, not a session, grant, fresh attempt,
/// payload observation or permission to replay. Session acquisition and its
/// partial/close custody remain with the existing Result access Owner.
pub fn NativeLocalReadPolicyBinding::resolve_submitted_result_in_original_read(
  self : NativeLocalReadPolicyBinding,
  selected : NativeClientOriginalRunSelection,
  service : @result_access.NativeResultAccessService,
  request : @result_access.NativeResultAccessRequest,
  observed_at : String,
  now : Double,
) -> Result[NativeClientSubmittedRunAdmission, NativeLocalReadBindingIssue] {
  guard self.capture is Some(capture) else {
    return Err(Adoption(OriginalResourceScopePending))
  }
  read_binding_in_original_read(capture, (host, operations) => {
    if !physical_equal(host, self.host) ||
      selected.scope != self.scope ||
      request.run_definition_cid !=
      @publication.publication_contract_identity(selected.definition) {
      return Err(SelectionMismatch)
    }
    let facts : @result_access.NativeResultReadFacts = {
      request,
      public_index_entry_cid: "",
      result_manifest_cid: "",
      result_artifact_cid: "",
      result_definition_cid: "",
      material_generation_cid: "",
      observed_at,
    }
    match self.require_request(selected.request, facts) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let current = () => self.require_request(selected.request, facts) is Ok(_)
    let admission = match
      host.journal.resolve_submitted_result_binding(
        host.epoch,
        selected.reference,
        self.scope,
        current,
        now,
        service,
        request.namespace_id,
        operations=Some(operations),
      ) {
      Ok(value) => value
      Err(issue) => return Err(SubmittedResult(issue))
    }
    if @host.client_request_identity_relation(
        admission.request,
        selected.request,
      ) !=
      @host.SameRequest ||
      admission.run_definition_cid != request.run_definition_cid {
      return Err(SelectionMismatch)
    }
    match self.require_request(selected.request, facts) {
      Err(issue) => Err(issue)
      Ok(_) => Ok(admission)
    }
  })
}
