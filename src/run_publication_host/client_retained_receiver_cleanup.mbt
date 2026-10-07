///|
/// Recover the original receiver cleanup address when a cancelled consumer
/// never received its input envelope. The saved checked edge, plan and receipt
/// identify the acquired responsibility; no replacement input is issued.
/// The physical caller must check its exclusive stop/cancellation authority,
/// current Site generation and actual reader/holding before reclamation.
pub fn prepare_client_retained_receiver_cleanup_from_plan(
  edge : ClientRetainedInputEdge,
  producer_record : @remote.DispatchRecord,
  producer_evidence : @remote.RemoteExecutionEvidence,
  producer_subject : @remote.RemoteManagedOutputSubject,
  producer_measurement : @remote.RemoteManagedOutputMeasurement,
  intent : @remote.RemoteRetainedInputIntent,
  result : @remote.RemoteRetainedInputResult,
  original_consumer : @remote.DispatchRequest,
  consumer_record : @remote.DispatchRecord,
  max_binding_bytes : Int,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[ClientRetainedInputCleanup, ClientRetainedTaskInputIssue] {
  let producer = @remote.dispatch_record_request(producer_record)
  let codes = @remote.dispatch_record_state_codes(consumer_record)
  if !@remote.dispatch_record_matches_request(
      consumer_record, original_consumer,
    ) ||
    codes[0] != 5 ||
    codes[2] != 2 ||
    @remote.dispatch_request_task_scope(producer) !=
    (edge.run_definition_cid, edge.producer.node_id) ||
    @remote.dispatch_request_task_scope(original_consumer) !=
    (edge.run_definition_cid, edge.consumer.node_id) ||
    @remote.dispatch_request_journal_key(producer)[0] !=
    @remote.dispatch_request_journal_key(original_consumer)[0] ||
    @remote.dispatch_request_execution_scope(producer) !=
    @remote.dispatch_request_execution_scope(original_consumer) {
    return Err(InvalidBinding)
  }
  // Historical producer cleanup evidence remains valid after release. It does
  // not restore live producer material, current use grants or a start claim.
  guard @remote.remote_execution_evidence_json(producer_evidence)
    is Ok(evidence) &&
    @remote.remote_managed_output_subject_json(producer_subject) is Ok(subject) &&
    @remote.remote_managed_output_measurement_json(producer_measurement)
    is Ok(measurement) else {
    return Err(ProducerUnavailable)
  }
  if @remote.admit_remote_managed_output_observation(
      producer_record,
      evidence,
      @remote.remote_execution_evidence_cid(producer_evidence),
      subject,
      @remote.remote_managed_output_subject_cid(producer_subject),
      measurement,
      @remote.remote_managed_output_measurement_cid(producer_measurement),
    )
    is Err(_) {
    return Err(ProducerUnavailable)
  }
  let selected = @remote.remote_retained_input_intent_projection(intent)
  let expected_intent = match
    @remote.prepare_remote_retained_input_intent(producer, {
      ..selected,
      consumer_input_port: edge.input_port,
      consumer_logical_cid: edge.consumer.logical_cid,
      consumer_task_key: edge.consumer.node_id,
      producer_evidence_cid: @remote.remote_execution_evidence_cid(
        producer_evidence,
      ),
      producer_logical_cid: edge.producer.logical_cid,
      producer_output_port: edge.producer.output_port,
      producer_schema_cid: edge.producer_schema_cid,
      producer_subject_cid: @remote.remote_managed_output_subject_cid(
        producer_subject,
      ),
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  if @remote.remote_retained_input_intent_identity(intent) !=
    @remote.remote_retained_input_intent_identity(expected_intent) ||
    @remote.remote_retained_input_intent_json(intent) !=
    @remote.remote_retained_input_intent_json(expected_intent) {
    return Err(InvalidBinding)
  }
  let plan = @remote.remote_retained_input_result_plan(result)
  let request = @remote.remote_retained_input_plan_transfer(plan)
  if @transfer.request_route(request) != @transfer.DirectStream {
    return Err(ForeignTransfer)
  }
  let expected_plan = match
    @remote.prepare_remote_retained_input_plan(
      intent, producer_subject, producer_evidence, request,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignTransfer)
  }
  if @remote.remote_retained_input_plan_identity(plan) !=
    @remote.remote_retained_input_plan_identity(expected_plan) ||
    @remote.remote_retained_input_plan_json(plan) !=
    @remote.remote_retained_input_plan_json(expected_plan) {
    return Err(ForeignTransfer)
  }
  let receipt = @remote.remote_retained_input_result_receipt(result)
  match
    @remote.prepare_remote_retained_input_result(
      plan,
      @remote.remote_retained_input_result_record(result),
      receipt,
    ) {
    Ok(_) => ()
    Err(_) => return Err(ForeignTransfer)
  }
  let physical = match
    prepare_client_transfer_input(
      request,
      "direct-destination",
      @transfer.destination_receipt_cid(receipt),
      max_binding_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  // Apply the same physical decoding bounds as existing cleanup addresses.
  // This value is opaque and cannot be used as a retained execution binding.
  match
    admit_client_transfer_input(
      physical.binding,
      max_binding_bytes,
      max_chunks,
      max_manifest_bytes,
      max_referenced_bytes,
    ) {
    Ok(_) => ()
    Err(_) => return Err(InvalidBinding)
  }
  Ok({
    physical,
    reader_id: @remote.dispatch_request_identity(original_consumer),
  })
}
