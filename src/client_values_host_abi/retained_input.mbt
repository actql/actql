///|
/// Resolve the original checked consumer edge. This value grants neither
/// execution nor access to retained material; producer evidence and Transfer
/// custody must still be admitted by their existing owners.
#export_name("clientValuesHostRetainedInputEdge")
pub fn client_values_host_retained_input_edge(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  consumer_task : Int,
  input_index : Int,
) -> Result[@host.ClientRetainedInputEdge, @host.ClientRetainedInputIssue] {
  @host.prepare_client_retained_input_edge(
    prepared, compilation, admission, definition, consumer_task, input_index,
  )
}

///|
#export_name("clientValuesHostRetainedInputEdgeFacts")
pub fn client_values_host_retained_input_edge_facts(
  edge : @host.ClientRetainedInputEdge,
) -> Array[String] {
  let facts = @host.client_retained_input_edge_projection(edge)
  facts.push(@host.client_retained_input_edge_schema_cid(edge))
  facts
}

///|
fn client_host_current_retained_coordinator(
  read_current : () -> Array[String],
) -> (
  @remote.DurableCoordinatorDispatchRecord,
  @remote.CoordinatorDispatchIntentRecord,
)? {
  let snapshot = read_current()
  if snapshot.length() != 2 ||
    snapshot[0].is_empty() ||
    snapshot[1].length() > 1048576 {
    return None
  }
  let durable = match
    @remote.admit_durable_coordinator_dispatch_record(@utf8.encode(snapshot[1])) {
    Ok(value) => value
    Err(_) => return None
  }
  let journal = match @remote.create_coordinator_dispatch_journal(snapshot[0]) {
    Ok(value) => value
    Err(_) => return None
  }
  let record = match
    @remote.restore_durable_coordinator_dispatch_record(journal, durable) {
    Ok(value) => value
    Err(_) => return None
  }
  Some((durable, record))
}

///|
/// The callback reads an atomic current snapshot from the trusted Coordinator
/// owner. Saved material never supplies its own current observation. Every
/// availability check re-admits that owner snapshot and its accepted history.
#export_name("clientValuesHostRetainedInputProducer")
pub fn client_values_host_retained_input_producer(
  edge : @host.ClientRetainedInputEdge,
  read_current : () -> Array[String],
) -> Result[@host.ClientRetainedInputProducer, @host.ClientRetainedInputIssue] {
  guard client_host_current_retained_coordinator(read_current)
    is Some((durable, _)) &&
    @remote.durable_coordinator_dispatch_record_evidence(durable)
    is Some(evidence) &&
    @remote.durable_coordinator_dispatch_record_subject(durable)
    is Some(subject) &&
    @remote.durable_coordinator_dispatch_record_measurement(durable)
    is Some(measurement) else {
    return Err(@host.ProducerUnavailable)
  }
  @host.prepare_client_coordinator_retained_input_producer(
    edge,
    @remote.durable_coordinator_dispatch_record_request(durable),
    evidence,
    subject,
    measurement,
    () => {
      client_host_current_retained_coordinator(read_current).map(pair => pair.1)
    },
  )
}

///|
#export_name("clientValuesHostRetainedInputProducerAvailable")
pub fn client_values_host_retained_input_producer_available(
  producer : @host.ClientRetainedInputProducer,
) -> Bool {
  @host.client_retained_input_producer_available(producer)
}

///|
/// Canonical evidence projection is not material access or execution authority.
#export_name("clientValuesHostRetainedInputProducerFacts")
pub fn client_values_host_retained_input_producer_facts(
  producer : @host.ClientRetainedInputProducer,
) -> Result[Array[String], @remote.DispatchIssue] {
  let request = @host.client_retained_input_producer_dispatch(producer)
  let evidence = @host.client_retained_input_producer_evidence(producer)
  let subject = @host.client_retained_input_producer_subject(producer)
  let request_wire = match @remote.dispatch_request_json(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let evidence_wire = match @remote.remote_execution_evidence_json(evidence) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let subject_wire = match @remote.remote_managed_output_subject_json(subject) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok([
    @remote.dispatch_request_identity(request),
    request_wire,
    @remote.remote_execution_evidence_cid(evidence),
    evidence_wire,
    @remote.remote_managed_output_subject_cid(subject),
    subject_wire,
  ])
}
