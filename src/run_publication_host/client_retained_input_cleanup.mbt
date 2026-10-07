///|
/// The exact receiver named by a completed consumer's original binding.
/// This value grants no execution, current borrow or payload access. The
/// physical caller must establish exclusive stop before returning the reader.
struct ClientRetainedInputCleanup {
  physical : ClientTransferInput
  reader_id : String
}

///|
/// Recover an existing cleanup address from the original accepted binding,
/// not from a freshly compiled graph. Both settled occurrences and their
/// durable completion evidence must be admitted independently. Cleanup does
/// not issue a replacement edge, authorize execution or refresh any lifetime.
pub fn prepare_client_retained_input_cleanup(
  binding : @remote.RemoteInputBinding,
  producer_record : @remote.DispatchRecord,
  producer_evidence : @remote.RemoteExecutionEvidence,
  producer_subject : @remote.RemoteManagedOutputSubject,
  producer_measurement : @remote.RemoteManagedOutputMeasurement,
  consumer_record : @remote.DispatchRecord,
  consumer_evidence : @remote.RemoteExecutionEvidence,
  consumer_subject : @remote.RemoteManagedOutputSubject,
  consumer_measurement : @remote.RemoteManagedOutputMeasurement,
  max_binding_bytes : Int,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[ClientRetainedInputCleanup, ClientRetainedTaskInputIssue] {
  if @remote.verify_remote_completed_cleanup_observation(
      producer_record, producer_evidence, producer_subject, producer_measurement,
    )
    is Err(_) ||
    @remote.verify_remote_completed_cleanup_observation(
      consumer_record, consumer_evidence, consumer_subject, consumer_measurement,
    )
    is Err(_) {
    return Err(ProducerUnavailable)
  }
  let producer = @remote.dispatch_record_request(producer_record)
  let consumer = @remote.dispatch_record_request(consumer_record)
  let (run, task) = @remote.dispatch_request_task_scope(consumer)
  let producer_scope = @remote.dispatch_request_task_scope(producer)
  if producer_scope.0 != run ||
    producer_scope.1 == task ||
    @remote.dispatch_request_journal_key(producer)[0] !=
    @remote.dispatch_request_journal_key(consumer)[0] ||
    @remote.dispatch_request_execution_scope(producer) !=
    @remote.dispatch_request_execution_scope(consumer) ||
    !@remote.remote_input_binding_matches_dispatch(binding, consumer) {
    return Err(InvalidBinding)
  }
  let node = match
    @source.parse_json_bytes(
      @utf8.encode(@remote.remote_input_binding_body(binding)),
      { max_input_bytes: max_binding_bytes, max_nodes: 32, max_depth: 2, },
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let cursor = match
    @decode.admit(node, {
      max_nodes: 32,
      max_depth: 2,
      max_string_bytes: max_binding_bytes,
      max_total_string_bytes: max_binding_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let fields = match
    @decode.closed_object(cursor, [
      "consumer_input_port", "consumer_logical_cid", "consumer_task_key", "destination_receipt_json",
      "physical_input_json", "producer_evidence_json", "producer_logical_cid", "producer_output_port",
      "producer_request_json", "producer_subject_json", "run_definition_cid", "version",
    ]) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let text = key => client_transfer_input_text(fields, key)
  for
    key in [
      "consumer_input_port", "consumer_logical_cid", "consumer_task_key", "destination_receipt_json",
      "physical_input_json", "producer_evidence_json", "producer_logical_cid", "producer_output_port",
      "producer_request_json", "producer_subject_json", "run_definition_cid", "version",
    ] {
    guard text(key) is Some(value) && !value.is_empty() else {
      return Err(InvalidBinding)
    }
  }
  if text("version") != Some("actql-remote-retained-task-input/0.1") ||
    text("run_definition_cid") != Some(run) ||
    text("consumer_task_key") != Some(task) ||
    text("producer_request_json") !=
    @remote.dispatch_request_json(producer).to_option() ||
    text("producer_evidence_json") !=
    @remote.remote_execution_evidence_json(producer_evidence).to_option() ||
    text("producer_subject_json") !=
    @remote.remote_managed_output_subject_json(producer_subject).to_option() {
    return Err(InvalidBinding)
  }
  guard text("physical_input_json") is Some(body) &&
    text("destination_receipt_json") is Some(receipt_wire) else {
    return Err(InvalidBinding)
  }
  let physical_binding = match
    @remote.prepare_remote_input_binding(body, max_binding_bytes) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let physical = match
    admit_client_transfer_input(
      physical_binding, max_binding_bytes, max_chunks, max_manifest_bytes, max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let request = client_transfer_request(physical)
  let scope = @remote.dispatch_request_execution_scope(producer)
  let facts = @transfer.request_projection(request)
  let subject = @remote.remote_managed_output_subject_projection(
    producer_subject,
  )
  if @transfer.request_route(request) != @transfer.DirectStream ||
    client_transfer_destination_use_id(physical) != "direct-destination" ||
    @transfer.request_journal_key(request)[0] !=
    @remote.dispatch_request_journal_key(producer)[0] ||
    facts[2] != scope[0] ||
    facts[3] != scope[1] ||
    facts[4] != scope[0] ||
    facts[5] != scope[1] ||
    facts[6] != subject[1] ||
    facts[7] != subject[7] ||
    @transfer.request_schema_contract_cid(request) != subject[4] ||
    @transfer.request_view_contract_cid(request) != subject[5] ||
    @transfer.request_codec_contract_cid(request) != subject[6] ||
    @transfer.request_row_count(request).to_string() != subject[9] ||
    @transfer.request_manifest(request).referenced_bytes.to_string() !=
    subject[10] {
    return Err(ForeignTransfer)
  }
  let receipt = match
    @transfer.admit_destination_receipt_json(
      receipt_wire,
      request,
      client_transfer_destination_receipt_cid(physical),
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignTransfer)
  }
  if @transfer.destination_receipt_projection(receipt)[4] == facts[6] {
    return Err(ForeignTransfer)
  }
  Ok({ physical, reader_id: @remote.dispatch_request_identity(consumer), })
}

///|
pub fn client_retained_input_cleanup_transfer(
  value : ClientRetainedInputCleanup,
) -> @transfer.RemoteTransferRequest {
  client_transfer_request(value.physical)
}

///|
pub fn client_retained_input_cleanup_receipt_cid(
  value : ClientRetainedInputCleanup,
) -> String {
  client_transfer_destination_receipt_cid(value.physical)
}

///|
pub fn client_retained_input_cleanup_reader_id(
  value : ClientRetainedInputCleanup,
) -> String {
  value.reader_id
}
