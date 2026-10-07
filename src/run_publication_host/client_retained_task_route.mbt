///|
/// Historical routing and cleanup facts bound to one checked input edge.
/// This value owns no current authority, borrow, start claim or reservation.
struct ClientRetainedTaskRoute {
  binding : @remote.RemoteInputBinding
  consumer_request : @remote.DispatchRequest
  producer_request : @remote.DispatchRequest
  producer_evidence : @remote.RemoteExecutionEvidence
  producer_subject : @remote.RemoteManagedOutputSubject
  physical : ClientTransferInput
  receipt : @transfer.RemoteTransferDestinationReceipt
}

///|
pub fn admit_client_retained_task_route(
  saved : @remote.RemoteInputBinding,
  edge : ClientRetainedInputEdge,
  consumer : @remote.DispatchRequest,
  max_binding_bytes : Int,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[ClientRetainedTaskRoute, ClientRetainedTaskInputIssue] {
  if !@remote.remote_input_binding_matches_dispatch(saved, consumer) ||
    @remote.dispatch_request_task_scope(consumer) !=
    (edge.run_definition_cid, edge.consumer.node_id) {
    return Err(InvalidBinding)
  }
  let fields = match retained_task_binding_fields(saved, max_binding_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard client_transfer_input_text(fields, "version") ==
    Some("actql-remote-retained-task-input/0.1") &&
    client_transfer_input_text(fields, "consumer_input_port") ==
    Some(edge.input_port) &&
    client_transfer_input_text(fields, "consumer_logical_cid") ==
    Some(edge.consumer.logical_cid) &&
    client_transfer_input_text(fields, "consumer_task_key") ==
    Some(edge.consumer.node_id) &&
    client_transfer_input_text(fields, "producer_logical_cid") ==
    Some(edge.producer.logical_cid) &&
    client_transfer_input_text(fields, "producer_output_port") ==
    Some(edge.producer.output_port) &&
    client_transfer_input_text(fields, "run_definition_cid") ==
    Some(edge.run_definition_cid) &&
    client_transfer_input_text(fields, "producer_request_json")
    is Some(request_json) &&
    client_transfer_input_text(fields, "producer_evidence_json")
    is Some(evidence_json) &&
    client_transfer_input_text(fields, "producer_subject_json")
    is Some(subject_json) &&
    client_transfer_input_text(fields, "physical_input_json")
    is Some(physical_json) &&
    client_transfer_input_text(fields, "destination_receipt_json")
    is Some(receipt_json) else {
    return Err(InvalidBinding)
  }
  guard @sha.text_hex(request_json) is Ok(request_hash) &&
    @remote.admit_dispatch_request_json(request_json, "sha256:" + request_hash)
    is Ok(producer_request) &&
    @remote.dispatch_request_task_scope(producer_request) ==
    (edge.run_definition_cid, edge.producer.node_id) &&
    @sha.text_hex(evidence_json) is Ok(evidence_hash) &&
    @remote.admit_remote_execution_evidence_json(
      evidence_json,
      "sha256:" + evidence_hash,
      producer_request,
    )
    is Ok(evidence) &&
    @sha.text_hex(subject_json) is Ok(subject_hash) &&
    @remote.admit_remote_managed_output_subject_json(
      subject_json,
      "sha256:" + subject_hash,
      producer_request,
    )
    is Ok(subject) &&
    @remote.remote_managed_output_subject_matches_evidence(
      subject, evidence, producer_request,
    ) else {
    return Err(InvalidBinding)
  }
  guard @remote.prepare_remote_input_binding(physical_json, max_binding_bytes)
    is Ok(physical_binding) &&
    admit_client_transfer_input(
      physical_binding, max_binding_bytes, max_chunks, max_manifest_bytes, max_referenced_bytes,
    )
    is Ok(physical) &&
    @transfer.admit_destination_receipt_json(
      receipt_json,
      physical.request,
      physical.destination_receipt_cid,
    )
    is Ok(receipt) else {
    return Err(ForeignTransfer)
  }
  let source_scope = @remote.dispatch_request_execution_scope(producer_request)
  let consumer_scope = @remote.dispatch_request_execution_scope(consumer)
  let facts = @transfer.request_projection(physical.request)
  let subject_facts = @remote.remote_managed_output_subject_projection(subject)
  let authority = @remote.dispatch_request_journal_key(consumer)[0]
  if @remote.dispatch_request_journal_key(producer_request)[0] != authority ||
    @transfer.request_journal_key(physical.request)[0] != authority ||
    facts[2] != source_scope[0] ||
    facts[3] != source_scope[1] ||
    facts[4] != consumer_scope[0] ||
    facts[5] != consumer_scope[1] ||
    facts[6] != subject_facts[1] ||
    facts[7] != subject_facts[7] ||
    subject_facts[4] != edge.producer_schema_cid ||
    @transfer.request_schema_contract_cid(physical.request) != subject_facts[4] ||
    @transfer.request_view_contract_cid(physical.request) != subject_facts[5] ||
    @transfer.request_codec_contract_cid(physical.request) != subject_facts[6] ||
    @transfer.request_row_count(physical.request).to_string() !=
    subject_facts[9] ||
    @transfer.request_manifest(physical.request).referenced_bytes.to_string() !=
    subject_facts[10] ||
    @transfer.destination_receipt_projection(receipt)[4] == facts[6] {
    return Err(ForeignTransfer)
  }
  // Reconstruct the original closed canonical body. Parsing equal-looking
  // nested JSON or matching a schema alone does not identify this occurrence.
  guard @remote.dispatch_request_json(producer_request) is Ok(canonical_request) &&
    @remote.remote_execution_evidence_json(evidence) is Ok(canonical_evidence) &&
    @remote.remote_managed_output_subject_json(subject) is Ok(canonical_subject) &&
    @transfer.destination_receipt_json(receipt) is Ok(canonical_receipt) else {
    return Err(InvalidBinding)
  }
  let canonical = try {
    let writer = @encode.writer(max_binding_bytes, 32, 2)
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("consumer_input_port", edge.input_port),
        ("consumer_logical_cid", edge.consumer.logical_cid),
        ("consumer_task_key", edge.consumer.node_id),
        ("destination_receipt_json", canonical_receipt),
        (
          "physical_input_json",
          @remote.remote_input_binding_body(physical.binding),
        ),
        ("producer_evidence_json", canonical_evidence),
        ("producer_logical_cid", edge.producer.logical_cid),
        ("producer_output_port", edge.producer.output_port),
        ("producer_request_json", canonical_request),
        ("producer_subject_json", canonical_subject),
        ("run_definition_cid", edge.run_definition_cid),
        ("version", "actql-remote-retained-task-input/0.1"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  if canonical != @remote.remote_input_binding_body(saved) {
    return Err(InvalidBinding)
  }
  Ok({
    binding: saved,
    consumer_request: consumer,
    producer_request,
    producer_evidence: evidence,
    producer_subject: subject,
    physical,
    receipt,
  })
}

///|
pub fn client_retained_task_route_producer_dispatch(
  value : ClientRetainedTaskRoute,
) -> @remote.DispatchRequest {
  value.producer_request
}

///|
pub fn client_retained_task_route_physical(
  value : ClientRetainedTaskRoute,
) -> ClientTransferInput {
  value.physical
}

///|
pub fn client_retained_task_route_receipt(
  value : ClientRetainedTaskRoute,
) -> @transfer.RemoteTransferDestinationReceipt {
  value.receipt
}
