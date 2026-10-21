///|
/// Check the current explicit selection before the existing Result owner
/// resolves a payload. Possession of an attempt or a saved grant is not allow.
pub fn NativeLocalReadPolicyBinding::authorize_read_request(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  request : @result_access.NativeResultAccessRequest,
  observed_at : String,
  max_output_bytes? : Int? = None,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  match self.capture {
    None =>
      self.authorize_read_request_with_reads(
        original,
        request,
        observed_at,
        max_output_bytes~,
      )
    Some(capture) =>
      read_binding_in_original_read(capture, (host, operations) => {
        if !physical_equal(host, self.host) {
          return Err(SelectionMismatch)
        }
        self.authorize_read_request_with_reads(
          original,
          request,
          observed_at,
          max_output_bytes~,
          reads=Some(operations.reads),
        )
      })
  }
}

///|
fn NativeLocalReadPolicyBinding::authorize_read_request_with_reads(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  request : @result_access.NativeResultAccessRequest,
  observed_at : String,
  max_output_bytes? : Int? = None,
  reads? : NativeClientJournalReadAccess? = None,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  if max_output_bytes is Some(limit) &&
    (limit < 1 || limit > self.selection.max_bytes) {
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
  match self.require_request(original, facts) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let record = match
    self.host.journal.lookup_with_reads(original, true, reads~) {
    Ok(Retained(value)) => value
    Ok(UnresolvedHistory) => return Err(Journal(CustodyLost))
    Err(issue) => return Err(Journal(issue))
  }
  if @publication.publication_contract_identity(record.definition) !=
    request.run_definition_cid {
    return Err(Journal(ForeignRun))
  }
  self.require_request(original, facts)
}

///|
// Read-only transaction: missing evidence or reservation is never repaired by
// delivery authorization. The original admission must already be committed.
fn NativeLocalReadPolicyBinding::retained_read_admission(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  actual_policy_cid : String,
) -> Result[
  @result_access.NativeResultReadAdmission,
  NativeLocalReadBindingIssue,
] {
  match self.capture {
    None =>
      self.retained_read_admission_with_operations(
        original, facts, actual_policy_cid,
      )
    Some(capture) =>
      read_binding_in_original_read(capture, (host, operations) => {
        if !physical_equal(host, self.host) {
          return Err(SelectionMismatch)
        }
        self.retained_read_admission_with_operations(
          original,
          facts,
          actual_policy_cid,
          operations=Some(operations),
        )
      })
  }
}

///|
fn NativeLocalReadPolicyBinding::retained_read_admission_with_operations(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  facts : @result_access.NativeResultReadFacts,
  actual_policy_cid : String,
  operations? : NativeClientJournalOperationAccess? = None,
) -> Result[
  @result_access.NativeResultReadAdmission,
  NativeLocalReadBindingIssue,
] {
  let reads = operations.map(value => value.reads)
  let mut refusal : NativeLocalReadBindingIssue? = None
  let retained = self.host.journal.transaction_with_reads(
    () => {
      let bodies = match
        self.read_admission_originals(original, facts, actual_policy_cid) {
        Ok(value) => value
        Err(issue) => {
          refusal = Some(issue)
          return Err(AuthorizationDenied)
        }
      }
      match
        self.host.require_retained_read_evidence_target(original, operations~) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      let packet = match local_read_evidence_packet(original, bodies) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      guard read_client_journal_value(
          self.host.database,
          "client_local_read_evidence",
          bodies.egress.cid,
          reads,
        )
        is Ok(row) &&
        row.revision == 0L &&
        row.body == packet else {
        return Err(CustodyLost)
      }
      match self.require_request(original, facts) {
        Err(issue) => {
          refusal = Some(issue)
          Err(AuthorizationDenied)
        }
        Ok(_) => {
          let admission : @result_access.NativeResultReadAdmission = {
            authorization_context_cid: bodies.authorization.cid,
            data_ceiling_cid: bodies.ceiling.cid,
            egress_admission_cid: bodies.egress.cid,
            expires_at: self.expires_at,
            max_bytes: self.selection.max_bytes,
            max_uses: self.selection.max_uses,
          }
          Ok(admission)
        }
      }
    },
    reads~,
  )
  match retained {
    Ok(value) => Ok(value)
    Err(TransactionUnknown) => Err(Journal(TransactionUnknown))
    Err(issue) => Err(refusal.unwrap_or(Journal(issue)))
  }
}

///|
/// Recheck current authority and original custody before chunk disclosure or
/// receipt commit. Recompute the existing issuer's identity, without issuing
/// a replacement grant, reserving more metadata, or inventing an attempt.
pub fn NativeLocalReadPolicyBinding::authorize_read_delivery(
  self : NativeLocalReadPolicyBinding,
  original : @host.ClientRequestIdentity,
  store : @publication_store.Store,
  delivery : @result_access.NativeResultDeliveryAuthorization,
) -> Result[Unit, NativeLocalReadBindingIssue] {
  if delivery.stage == "table_output" {
    guard self.selection.sink == Material &&
      self.selection.purpose == "cli-table" &&
      self.material_receiver is Some(receiver) &&
      receiver.table_output_in_flight() else {
      return Err(AuthorizationDenied)
    }
  }
  if delivery.stage != "read" &&
    delivery.stage != "receipt" &&
    delivery.stage != "table_output" {
    return Err(SelectionMismatch)
  }
  match
    self.authorize_read_request(
      original,
      delivery.request,
      delivery.observed_at,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let resolved = match
    store.resolve_committed_result(
      delivery.request.namespace_id,
      delivery.request.authority_scope_cid,
      delivery.request.run_definition_cid,
      delivery.request.result_name,
      65536,
      8192,
      64,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Journal(CustodyLost))
    Err(issue) => return Err(Journal(PublicationObservation(issue)))
  }
  if delivery.public_index_entry_cid !=
    @publication.publication_contract_identity(resolved.public_index_entry) ||
    delivery.result_manifest_cid !=
    @publication.publication_contract_identity(resolved.result_manifest) {
    return Err(Journal(ForeignRun))
  }
  let facts : @result_access.NativeResultReadFacts = {
    request: delivery.request,
    public_index_entry_cid: delivery.public_index_entry_cid,
    result_manifest_cid: delivery.result_manifest_cid,
    result_artifact_cid: resolved.read.result_artifact_cid,
    result_definition_cid: resolved.read.result_definition_cid,
    material_generation_cid: resolved.read.material_generation_cid,
    observed_at: delivery.observed_at,
  }
  let policy = match self.resolve_policy_original(original, store, facts) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let admission = match
    self.retained_read_admission(
      original,
      facts,
      @publication.captured_effect_dependency_body_cid(policy),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let expected = match
    @publication.issue_result_read_grant(
      resolved.public_index_entry,
      resolved.result_manifest,
      [delivery.request.result_name],
      [delivery.request.format],
      delivery.request.principal_id,
      delivery.request.purpose,
      admission.data_ceiling_cid,
      admission.max_bytes,
      admission.max_uses,
      admission.expires_at,
      admission.authorization_context_cid,
      admission.egress_admission_cid,
      65536,
      8192,
      64,
    ) {
    Ok(value) => value
    Err(_) => return Err(Journal(CustodyLost))
  }
  if @publication.publication_contract_identity(expected) !=
    delivery.result_read_grant_cid {
    return Err(Journal(ForeignRun))
  }
  let saved = match
    store.read_publication_contract(
      "result_read_grant",
      delivery.result_read_grant_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(PublicationObservation(issue)))
  }
  if @publication.publication_contract_json(saved) !=
    @publication.publication_contract_json(expected) {
    return Err(Journal(CustodyLost))
  }
  self.require_request(original, facts)
}
