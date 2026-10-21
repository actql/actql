///|
/// Return only the same durable successful receipt after verifying the actual
/// file against its authenticated original identity and delivered bytes. This
/// never opens a payload session, issues a grant or retries a prior attempt.
pub fn NativeLocalReadPolicyBinding::completed_file_receipt_in_original_read(
  self : NativeLocalReadPolicyBinding,
  selected : NativeClientOriginalRunSelection,
  service : @result_access.NativeResultAccessService,
  request : @result_access.NativeResultAccessRequest,
  observed_at : String,
  now : Double,
) -> Result[String, NativeLocalReadBindingIssue] {
  guard self.selection.sink == File &&
    self.capture is Some(capture) &&
    self.file_destination is Some(destination) &&
    self.file_preparation is Some((original, prepared_request)) &&
    self.file_store is Some(store) &&
    @host.client_request_identity_relation(original, selected.request) ==
    @host.SameRequest &&
    local_read_file_same_request(prepared_request, request) else {
    return Err(SelectionMismatch)
  }
  let lookup = match
    self.lookup_submitted_result_delivery_in_original_read(
      selected, service, request, observed_at, now,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(FileOutputUnavailable)
    Err(issue) => return Err(issue)
  }
  guard lookup.record is Some(record) &&
    lookup.host_release_receipt is Some(receipt) &&
    @publication.validate_delivery_success_evidence(
      lookup.attempt,
      receipt,
      record,
    )
    is Ok(_) else {
    return Err(FileOutputUnavailable)
  }
  let wire = @publication.publication_contract_json(receipt)
  let saved = read_binding_in_original_read(capture, (host, operations) => {
    if !physical_equal(host, self.host) {
      return Err(SelectionMismatch)
    }
    // The successful receipt names this exact reserved holding and packet.
    // Unrelated retained evidence belongs to explicit audit/maintenance.
    match
      host.require_retained_read_evidence_target(
        selected.request,
        operations=Some(operations),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Journal(issue))
    }
    let receipt_fields = match
      local_read_evidence_object(
        @utf8.encode(wire),
        [
          "version", "run_definition_cid", "invocation_cid", "result_manifest_cid",
          "result_name", "result_artifact_cid", "serialization_contract_cid", "delivered_byte_count",
          "delivered_sha256", "authorization_context_cid", "egress_admission_cid",
          "result_delivery_receipt_cid",
        ],
        65536,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    guard epoch_text(receipt_fields, "egress_admission_cid") is Some(egress_cid) else {
      return Err(Journal(CustodyLost))
    }
    let row = match
      read_client_journal_value(
        host.database,
        "client_local_read_evidence",
        egress_cid,
        Some(operations.reads),
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(Physical(issue)))
    }
    match
      host.validate_read_evidence(
        self.crypto,
        { key: egress_cid, revision: row.revision, body: row.body, },
        operations=Some(operations),
        capture=Some(capture),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Journal(issue))
    }
    let packet = match
      local_read_evidence_object(
        row.body,
        ["authorization_context", "data_ceiling", "egress_admission", "request"],
        65536,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    guard epoch_text(packet, "request") is Some(request_wire) &&
      @host.admit_client_request_identity_record_wire(request_wire)
      is Ok(saved_request) &&
      @host.client_request_identity_relation(saved_request, selected.request) ==
      @host.SameRequest &&
      epoch_text(packet, "egress_admission") is Some(egress_wire) else {
      return Err(Journal(CustodyLost))
    }
    let fields = match local_read_egress_fields(egress_wire) {
      Ok(value) => value
      Err(issue) => return Err(Journal(issue))
    }
    for
      (key, expected) in [
        ("attempt_id", request.attempt_id),
        ("authority_scope_cid", request.authority_scope_cid),
        ("run_definition_cid", request.run_definition_cid),
        ("principal_id", request.principal_id),
        ("purpose", request.purpose),
        ("result_name", request.result_name),
        ("format", request.format),
        ("sink", "file"),
        ("read_original_cid", self.selection_cid),
      ] {
      if epoch_text(fields, key) != Some(expected) {
        return Err(SelectionMismatch)
      }
    }
    read_local_file_destination_original(fields).map_err(issue => Journal(issue))
  })
  let saved = match saved {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (count, digest) = match destination.verify_completed(saved) {
    Ok(value) => value
    Err(issue) => return Err(FileOutput(issue))
  }
  guard @host.admit_client_result_delivery_receipts(wire) is Ok(receipts) &&
    receipts.matching_identities(count, digest) is Ok(_) else {
    return Err(SelectionMismatch)
  }
  match self.prepare_destination_facts(original, store, request, observed_at) {
    Ok(_) => Ok(wire)
    Err(issue) => Err(issue)
  }
}

///|
fn local_read_file_same_request(
  left : @result_access.NativeResultAccessRequest,
  right : @result_access.NativeResultAccessRequest,
) -> Bool {
  left.namespace_id == right.namespace_id &&
  left.authority_scope_cid == right.authority_scope_cid &&
  left.run_definition_cid == right.run_definition_cid &&
  left.principal_id == right.principal_id &&
  left.purpose == right.purpose &&
  left.result_name == right.result_name &&
  left.format == right.format &&
  left.attempt_id == right.attempt_id
}
