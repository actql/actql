///|
/// One input edge of the original admitted Run. This reference contains no
/// execution permission, live material, borrow or capacity reservation.
pub struct ClientRetainedInputEdge {
  run_definition_cid : String
  producer : ClientTaskFragmentNode
  consumer : ClientTaskFragmentNode
  input_port : String
  producer_schema_cid : String
  producer_owner : @lower.BoundPrepared
  program : @context.ProgramSourceIdentity
}

///|
/// An exact completed producer occurrence, never an equal-content substitute.
/// Current physical custody must still be admitted by the Transfer owner.
pub struct ClientRetainedInputProducer {
  edge : ClientRetainedInputEdge
  request : @remote.DispatchRequest
  evidence : @remote.RemoteExecutionEvidence
  subject : @remote.RemoteManagedOutputSubject
  available : () -> Bool
}

///|
pub(all) enum ClientRetainedInputIssue {
  Run(ClientTaskRunBindingIssue)
  Fragment(ClientTaskFragmentIssue)
  MissingEdge
  ContractMismatch
  ForeignProducer
  ProducerUnavailable
}

///|
/// Resolve an input from the checked graph, including split-operation ports.
/// Callers cannot select another producer by supplying a matching schema.
pub fn prepare_client_retained_input_edge(
  prepared : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  consumer_task : Int,
  input_index : Int,
) -> Result[ClientRetainedInputEdge, ClientRetainedInputIssue] {
  let run = match
    bind_client_task_run(prepared, compilation, admission, definition) {
    Ok(value) => value
    Err(issue) => return Err(Run(issue))
  }
  let graph = prepared_client_graph(prepared)
  if consumer_task < 0 ||
    input_index < 0 ||
    consumer_task >= @strategy.graph_task_count(graph) {
    return Err(MissingEdge)
  }
  let mut selected = None
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return Err(MissingEdge)
    }
    if @strategy.data_edge_consumer(edge) == consumer_task &&
      @strategy.data_edge_input(edge) == input_index {
      if selected is Some(_) {
        return Err(MissingEdge)
      }
      selected = Some(edge)
    }
  }
  guard selected is Some(edge) else { return Err(MissingEdge) }
  let producer_task = @strategy.data_edge_producer(edge)
  if producer_task < 0 || producer_task >= consumer_task {
    return Err(MissingEdge)
  }
  let fragment = fn(task : Int) {
    issue_prepared_client_task_fragment(
      prepared,
      task,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    )
  }
  let producer = match fragment(producer_task) {
    Ok(value) => value
    Err(issue) => return Err(Fragment(issue))
  }
  let consumer = match fragment(consumer_task) {
    Ok(value) => value
    Err(issue) => return Err(Fragment(issue))
  }
  guard client_task_edge_input(graph, edge) is Some((input_port, carrier)) &&
    client_task_carrier_contract(carrier, 1000000, 100000, 100)
    is Some((sort, contract)) else {
    return Err(ContractMismatch)
  }
  if sort != producer.output_carrier || contract != producer.output_contract_cid {
    return Err(ContractMismatch)
  }
  // A Relation field-map schema is not its ordinary row object contract.
  // Keep the checked Carrier port contract above and derive physical schema
  // admission independently through the existing Relation schema owner.
  let producer_schema_cid = match @carrier.kind(carrier) {
    RelationKind => {
      guard @carrier.relation_rows(carrier) is Some(rows) &&
        @carrier.complete_schema(rows) is Some(schema) else {
        return Err(ContractMismatch)
      }
      match
        @execution.identify_relation_schema(schema, {
          max_fields: 100000,
          max_bytes: 1000000,
          max_nodes: 100000,
          max_depth: 100,
        }) {
        Ok(identity) => @execution.relation_schema_cid(identity)
        Err(_) => return Err(ContractMismatch)
      }
    }
    GraphKind | EventsKind | VectorsKind => contract
  }
  guard @strategy.graph_task_owner(graph, producer_task) is Some(producer_owner) else {
    return Err(MissingEdge)
  }
  Ok({
    run_definition_cid: client_task_run_binding_definition_cid(run),
    producer,
    consumer,
    input_port,
    producer_schema_cid,
    producer_owner,
    program: @checked.source_identity(@strategy.graph_program(graph)),
  })
}

///|
/// Join the exact dispatch, durable completion and its admitted output subject.
/// A historical completion without current retained material cannot issue a
/// new input. No JSON, caller-supplied task key or attempt label stands in for
/// these owned values.
pub fn prepare_client_retained_input_producer(
  edge : ClientRetainedInputEdge,
  record : @remote.DispatchRecord,
  evidence : @remote.RemoteExecutionEvidence,
  subject : @remote.RemoteManagedOutputSubject,
) -> Result[ClientRetainedInputProducer, ClientRetainedInputIssue] {
  let request = @remote.dispatch_record_request(record)
  if @remote.dispatch_request_task_scope(request) !=
    (edge.run_definition_cid, edge.producer.node_id) ||
    !@remote.remote_managed_output_subject_matches_evidence(
      subject, evidence, request,
    ) ||
    @remote.remote_managed_output_subject_projection(subject)[4] !=
    edge.producer_schema_cid {
    return Err(ForeignProducer)
  }
  let value = {
    edge,
    request,
    evidence,
    subject,
    available: () => {
      client_retained_site_producer_available(record, evidence, subject)
    },
  }
  if !client_retained_input_producer_available(value) {
    return Err(ProducerUnavailable)
  }
  Ok(value)
}

///|
/// Use the Coordinator's accepted observation, without constructing a Site
/// record or granting access to its material. The current-record port belongs
/// to the trusted Host owner; callers must retain its durable revision fence
/// across physical handoffs. Missing current custody fails closed.
pub fn prepare_client_coordinator_retained_input_producer(
  edge : ClientRetainedInputEdge,
  request : @remote.DispatchRequest,
  evidence : @remote.RemoteExecutionEvidence,
  subject : @remote.RemoteManagedOutputSubject,
  measurement : @remote.RemoteManagedOutputMeasurement,
  current : () -> @remote.CoordinatorDispatchIntentRecord?,
) -> Result[ClientRetainedInputProducer, ClientRetainedInputIssue] {
  if @remote.dispatch_request_task_scope(request) !=
    (edge.run_definition_cid, edge.producer.node_id) ||
    !@remote.remote_managed_output_subject_matches_evidence(
      subject, evidence, request,
    ) ||
    @remote.remote_managed_output_subject_projection(subject)[4] !=
    edge.producer_schema_cid {
    return Err(ForeignProducer)
  }
  let value = {
    edge,
    request,
    evidence,
    subject,
    available: () => {
      guard current() is Some(record) else { return false }
      if !@remote.coordinator_managed_output_matches(
          record, request, evidence, subject, measurement,
        ) {
        return false
      }
      let authority = @remote.dispatch_request_journal_key(request)[0]
      match
        @remote.coordinator_execution_observation(
          record,
          authority,
          edge.run_definition_cid,
          edge.producer.node_id,
        ) {
        Ok(observation) => observation.cleanup == Some(@remote.CleanupActive)
        Err(_) => false
      }
    },
  }
  if !client_retained_input_producer_available(value) {
    return Err(ProducerUnavailable)
  }
  Ok(value)
}

///|
/// Recheck the original mutable dispatch record before each custody handoff.
/// This does not prove that physical bytes are present or grant a read permit.
pub fn client_retained_input_producer_available(
  value : ClientRetainedInputProducer,
) -> Bool {
  (value.available)()
}

///|
fn client_retained_site_producer_available(
  record : @remote.DispatchRecord,
  evidence : @remote.RemoteExecutionEvidence,
  subject : @remote.RemoteManagedOutputSubject,
) -> Bool {
  if !@remote.remote_completion_evidence_available(record) {
    return false
  }
  let (_, state, cleanup, _, _) = @remote.dispatch_record_state(record)
  if cleanup != @remote.CleanupActive {
    return false
  }
  let (material, holding, _, _) = @remote.remote_managed_output_subject_retention(
    subject,
  )
  match state {
    @remote.EvidenceDurable(saved_material, saved_holding, saved_evidence) =>
      material == saved_material &&
      holding == saved_holding &&
      saved_evidence == @remote.remote_execution_evidence_cid(evidence)
    _ => false
  }
}

///|
/// Immutable checked ports; schema and order remain bound by the original
/// fragment identities rather than being reinterpreted by the Cloud caller.
pub fn client_retained_input_edge_projection(
  value : ClientRetainedInputEdge,
) -> Array[String] {
  [
    value.run_definition_cid,
    value.producer.node_id,
    value.producer.output_port,
    value.producer.logical_cid,
    value.producer.output_contract_cid,
    value.consumer.node_id,
    value.consumer.logical_cid,
    value.input_port,
  ]
}

///|
/// Physical output schema expected by the checked producer edge. For Relation
/// this is the complete field-map identity, separate from the Carrier port's
/// ordinary row object contract retained by the edge projection.
pub fn client_retained_input_edge_schema_cid(
  value : ClientRetainedInputEdge,
) -> String {
  value.producer_schema_cid
}

///|
pub fn client_retained_input_producer_dispatch(
  value : ClientRetainedInputProducer,
) -> @remote.DispatchRequest {
  value.request
}

///|
pub fn client_retained_input_producer_subject(
  value : ClientRetainedInputProducer,
) -> @remote.RemoteManagedOutputSubject {
  value.subject
}

///|
pub fn client_retained_input_producer_evidence(
  value : ClientRetainedInputProducer,
) -> @remote.RemoteExecutionEvidence {
  value.evidence
}

///|
pub fn client_retained_input_producer_edge(
  value : ClientRetainedInputProducer,
) -> ClientRetainedInputEdge {
  value.edge
}

///|
/// A transferred capture must use the original checked producer owner and
/// Program preparation, even if another preparation has equal row contracts.
/// Reconstruction first re-admits the Run and issues the edge again.
pub fn client_retained_input_capture_owner_matches(
  edge : ClientRetainedInputEdge,
  sequence : @query.QuerySequence,
  program : @context.ProgramSourceIdentity,
) -> Bool {
  physical_equal(edge.producer_owner, @query.query_sequence_owner(sequence)) &&
  physical_equal(edge.program, program)
}
