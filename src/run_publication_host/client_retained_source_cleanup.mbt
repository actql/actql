///|
/// A checked sole-consumer relationship, not physical stop or cleanup evidence.
/// The receiver borrow, receiver holding and producer file remain independent.
pub struct ClientRetainedSourceCleanup {
  binding : @remote.RemoteInputBinding
  producer : @remote.DispatchRequest
  consumer : @remote.DispatchRequest
  consumer_evidence_cid : String
  address : ClientRetainedInputCleanup
}

///|
/// Admit cleanup of the initial one-Source/two-task profile from the original
/// Run and checked edge. A matching schema or completed pair cannot substitute
/// for proving that this is the producer's only consumer and public Result.
/// This grants no execution, read, borrow, capacity return or terminal state.
pub fn prepare_client_retained_source_cleanup(
  materials : ClientRunMaterials,
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
) -> Result[ClientRetainedSourceCleanup, ClientRetainedTaskInputIssue] {
  let prepared = materials.prepared
  let graph = prepared_client_graph(prepared)
  guard materials.compilation is Tasks(compilation) else {
    return Err(InvalidBinding)
  }
  if @strategy.graph_task_count(graph) != 2 ||
    @strategy.graph_data_count(graph) != 1 ||
    @strategy.graph_program_has_effects(graph) ||
    prepared_client_acquisition_count(prepared) != 1 ||
    prepared_client_result_count(prepared) != 1 ||
    @strategy.graph_result_task(graph, 0) != Some(1) ||
    @strategy.graph_task_target(graph, 0) is Some(_) ||
    @strategy.graph_task_target(graph, 1) is None {
    return Err(InvalidBinding)
  }
  let edge = match
    prepare_client_retained_input_edge(
      prepared,
      compilation,
      materials.admission,
      materials.run_definition,
      1,
      0,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let producer = @remote.dispatch_record_request(producer_record)
  let consumer = @remote.dispatch_record_request(consumer_record)
  if @remote.dispatch_request_task_scope(producer) !=
    (edge.run_definition_cid, edge.producer.node_id) ||
    @remote.dispatch_request_task_scope(consumer) !=
    (edge.run_definition_cid, edge.consumer.node_id) {
    return Err(InvalidBinding)
  }
  // Read the original accepted binding with the same bounded decoder. Check
  // logical ports as well as the physical address before granting this scope.
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
  if text("consumer_input_port") != Some(edge.input_port) ||
    text("consumer_logical_cid") != Some(edge.consumer.logical_cid) ||
    text("producer_logical_cid") != Some(edge.producer.logical_cid) ||
    text("producer_output_port") != Some(edge.producer.output_port) ||
    @remote.remote_managed_output_subject_projection(producer_subject)[4] !=
    edge.producer_schema_cid {
    return Err(InvalidBinding)
  }
  let address = match
    prepare_client_retained_input_cleanup(
      binding, producer_record, producer_evidence, producer_subject, producer_measurement,
      consumer_record, consumer_evidence, consumer_subject, consumer_measurement,
      max_binding_bytes, max_chunks, max_manifest_bytes, max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    binding,
    producer,
    consumer,
    consumer_evidence_cid: @remote.remote_execution_evidence_cid(
      consumer_evidence,
    ),
    address,
  })
}

///|
pub fn client_retained_source_cleanup_requests(
  value : ClientRetainedSourceCleanup,
) -> (@remote.DispatchRequest, @remote.DispatchRequest) {
  (value.producer, value.consumer)
}

///|
/// Recheck the live journal's exact completion before physical cleanup. This
/// never accepts a different occurrence or changes the saved relationship.
pub fn verify_client_retained_source_cleanup_observation(
  value : ClientRetainedSourceCleanup,
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
) -> Result[Unit, ClientRetainedTaskInputIssue] {
  if @remote.dispatch_request_identity(
      @remote.dispatch_record_request(producer_record),
    ) !=
    @remote.dispatch_request_identity(value.producer) ||
    @remote.dispatch_request_identity(
      @remote.dispatch_record_request(consumer_record),
    ) !=
    @remote.dispatch_request_identity(value.consumer) ||
    @remote.remote_execution_evidence_cid(consumer_evidence) !=
    value.consumer_evidence_cid {
    return Err(InvalidBinding)
  }
  let address = match
    prepare_client_retained_input_cleanup(
      value.binding,
      producer_record,
      producer_evidence,
      producer_subject,
      producer_measurement,
      consumer_record,
      consumer_evidence,
      consumer_subject,
      consumer_measurement,
      max_binding_bytes,
      max_chunks,
      max_manifest_bytes,
      max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @transfer.request_cid(client_retained_input_cleanup_transfer(address)) !=
    @transfer.request_cid(client_retained_input_cleanup_transfer(value.address)) ||
    client_retained_input_cleanup_receipt_cid(address) !=
    client_retained_input_cleanup_receipt_cid(value.address) ||
    client_retained_input_cleanup_reader_id(address) !=
    client_retained_input_cleanup_reader_id(value.address) {
    return Err(InvalidBinding)
  }
  Ok(())
}
