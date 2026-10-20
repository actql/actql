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
  self.resolve_submitted_result_binding_original(
    selected, service, request, observed_at, now, false,
  )
}

///|
// Lookup has its independent current Run/named-Result authority. A File
// destination must not create a Writer or a new attempt just to inspect prior
// history; payload resolution below still requires the actual retained sink.
fn NativeLocalReadPolicyBinding::require_lookup_request(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  if self.selection.sink == File {
    self.require_request_selection(original, facts)
  } else {
    self.require_request(original, facts)
  }
}

///|
fn NativeLocalReadPolicyBinding::resolve_submitted_result_binding_original(
  self : NativeLocalReadPolicyBinding,
  selected : NativeClientOriginalRunSelection,
  service : @result_access.NativeResultAccessService,
  request : @result_access.NativeResultAccessRequest,
  observed_at : String,
  now : Double,
  lookup_only : Bool,
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
    let authorize = () => {
      if lookup_only {
        self.require_lookup_request(selected.request, facts)
      } else {
        self.require_request(selected.request, facts)
      }
    }
    match authorize() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let current = () => authorize() is Ok(_)
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
    match authorize() {
      Err(issue) => Err(issue)
      Ok(_) => Ok(admission)
    }
  })
}

///|
/// Lookup the same attempt's original history before any payload open. Absence
/// is not permission to replay; the caller must still use a fresh explicit
/// attempt and the existing read admission/delivery Owners. No session is
/// created inside the captured Journal callback.
pub fn NativeLocalReadPolicyBinding::lookup_submitted_result_delivery_in_original_read(
  self : NativeLocalReadPolicyBinding,
  selected : NativeClientOriginalRunSelection,
  service : @result_access.NativeResultAccessService,
  request : @result_access.NativeResultAccessRequest,
  observed_at : String,
  now : Double,
) -> Result[
  @publication_store.NativeResultDeliveryLookup?,
  NativeLocalReadBindingIssue,
] {
  match
    self.resolve_submitted_result_binding_original(
      selected, service, request, observed_at, now, true,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.capture is Some(capture) else {
    return Err(Adoption(OriginalResourceScopePending))
  }
  read_binding_in_original_read(capture, (host, _operations) => {
    if !physical_equal(host, self.host) {
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
    match self.require_lookup_request(selected.request, facts) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let observed = match
      @result_access.lookup_native_result_delivery_attempt(service, {
        namespace_id: request.namespace_id,
        authority_scope_cid: request.authority_scope_cid,
        run_definition_cid: request.run_definition_cid,
        principal_id: request.principal_id,
        purpose: request.purpose,
        result_name: request.result_name,
        attempt_id: request.attempt_id,
      }) {
      Ok(value) => value
      Err(issue) => return Err(SubmittedResult(ResultAccess(issue)))
    }
    match self.require_lookup_request(selected.request, facts) {
      Err(issue) => Err(issue)
      Ok(_) => Ok(observed)
    }
  })
}
