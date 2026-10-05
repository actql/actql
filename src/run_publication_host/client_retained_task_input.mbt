///|
/// Host-installed access to current trusted owners. None of these values is
/// reconstructed from the saved input body. Authorization must cover the
/// original Run/edge and both current Transfer grants; this port issues no
/// grant and is not an execution capability.
pub struct ClientRetainedInputCurrent {
  site_binding_current : (String, String, String) -> Bool
  authority : () -> String
  now_unix_ms : () -> Int64
  authorized : (ClientRetainedInputProducer, @transfer.RemoteTransferRequest) -> Bool
}

///|
pub fn install_client_retained_input_current(
  site : () -> @site.ExecutionSite,
  authority : () -> String,
  now_unix_ms : () -> Int64,
  authorized : (ClientRetainedInputProducer, @transfer.RemoteTransferRequest) -> Bool,
) -> ClientRetainedInputCurrent {
  install_client_retained_input_owner_current(
    (key, generation, bundle) => {
      let current = site()
      @site.site_key(current) == key &&
      @site.site_generation(current).to_string() == generation &&
      @site.site_binding_current(
        current,
        @site.site_generation(current),
        bundle,
      )
    },
    authority,
    now_unix_ms,
    authorized,
  )
}

///|
/// Install a trusted Host port to the existing current Site owner. It must
/// inspect the live identity/generation/bundle and availability, not saved
/// binding fields. This port creates no Site, reservation or grant.
pub fn install_client_retained_input_owner_current(
  site_binding_current : (String, String, String) -> Bool,
  authority : () -> String,
  now_unix_ms : () -> Int64,
  authorized : (ClientRetainedInputProducer, @transfer.RemoteTransferRequest) -> Bool,
) -> ClientRetainedInputCurrent {
  { site_binding_current, authority, now_unix_ms, authorized, }
}

///|
/// A checked consumer edge joined to the original durable producer and an
/// independently committed Transfer destination. The bytes are replayable
/// evidence, not a borrow, start claim or proof of physical cleanup.
pub struct ClientRetainedTaskInput {
  producer : ClientRetainedInputProducer
  transfer_record : @transfer.RemoteTransferRecord
  physical : ClientTransferInput
  binding : @remote.RemoteInputBinding
}

///|
pub(all) enum ClientRetainedTaskInputIssue {
  ProducerUnavailable
  ForeignTransfer
  TransferNotCommitted
  StaleSiteGeneration
  ForeignAuthority
  AuthorizationUnavailable
  TransferExpired
  InvalidBinding
  Encoding
}

///|
fn retained_task_input_current(
  producer : ClientRetainedInputProducer,
  transfer_record : @transfer.RemoteTransferRecord,
  current : ClientRetainedInputCurrent,
) -> Result[Unit, ClientRetainedTaskInputIssue] {
  if !client_retained_input_producer_available(producer) {
    return Err(ProducerUnavailable)
  }
  let current_authority = (current.authority)()
  let dispatch = client_retained_input_producer_dispatch(producer)
  let scope = @remote.dispatch_request_execution_scope(dispatch)
  let request = @transfer.record_request(transfer_record)
  let facts = @transfer.request_projection(request)
  if !(current.site_binding_current)(scope[0], scope[1], scope[2]) ||
    facts[2] != scope[0] ||
    facts[3] != scope[1] ||
    facts[4] != scope[0] ||
    facts[5] != scope[1] {
    return Err(StaleSiteGeneration)
  }
  // The trusted caller obtains current authority from the existing owner.
  // Saved request bytes cannot supply their own current authorization.
  if current_authority.is_empty() ||
    @remote.dispatch_request_journal_key(dispatch)[0] != current_authority ||
    @transfer.request_journal_key(request)[0] != current_authority {
    return Err(ForeignAuthority)
  }
  let subject = @remote.remote_managed_output_subject_projection(
    client_retained_input_producer_subject(producer),
  )
  if facts[6] != subject[1] ||
    facts[7] != subject[7] ||
    @transfer.request_schema_contract_cid(request) != subject[4] ||
    @transfer.request_view_contract_cid(request) != subject[5] ||
    @transfer.request_codec_contract_cid(request) != subject[6] ||
    @transfer.request_row_count(request).to_string() != subject[9] ||
    @transfer.request_manifest(request).referenced_bytes.to_string() !=
    subject[10] {
    return Err(ForeignTransfer)
  }
  if !@transfer.request_active_at(request, (current.now_unix_ms)()) {
    return Err(TransferExpired)
  }
  if !(current.authorized)(producer, request) {
    return Err(AuthorizationUnavailable)
  }
  if !@transfer.record_is_destination_committed(transfer_record) {
    return Err(TransferNotCommitted)
  }
  Ok(())
}

///|
pub fn prepare_client_retained_task_input(
  producer : ClientRetainedInputProducer,
  transfer_record : @transfer.RemoteTransferRecord,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  destination_use_id : String,
  current : ClientRetainedInputCurrent,
  max_binding_bytes : Int,
) -> Result[ClientRetainedTaskInput, ClientRetainedTaskInputIssue] {
  match retained_task_input_current(producer, transfer_record, current) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let request = @transfer.record_request(transfer_record)
  let receipt_json = match @transfer.destination_receipt_json(receipt) {
    Ok(value) => value
    Err(_) => return Err(ForeignTransfer)
  }
  // Re-admit the receipt against this exact request, not just its schema.
  if @transfer.admit_destination_receipt_json(
      receipt_json,
      request,
      @transfer.destination_receipt_cid(receipt),
    )
    is Err(_) {
    return Err(ForeignTransfer)
  }
  if @transfer.destination_receipt_projection(receipt)[4] ==
    @transfer.request_projection(request)[6] {
    // A destination must adopt its own material generation. A source holding
    // or process-local handle cannot substitute for an independent Transfer.
    return Err(ForeignTransfer)
  }
  let physical = match
    prepare_client_transfer_input(
      request,
      destination_use_id,
      @transfer.destination_receipt_cid(receipt),
      max_binding_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let dispatch_json = match
    @remote.dispatch_request_json(
      client_retained_input_producer_dispatch(producer),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let evidence_json = match
    @remote.remote_execution_evidence_json(
      client_retained_input_producer_evidence(producer),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let subject_json = match
    @remote.remote_managed_output_subject_json(
      client_retained_input_producer_subject(producer),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let edge = client_retained_input_edge_projection(
    client_retained_input_producer_edge(producer),
  )
  let body = try {
    let writer = @encode.writer(max_binding_bytes, 32, 2)
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("consumer_input_port", edge[7]),
        ("consumer_logical_cid", edge[6]),
        ("consumer_task_key", edge[5]),
        ("destination_receipt_json", receipt_json),
        (
          "physical_input_json",
          @remote.remote_input_binding_body(physical.binding),
        ),
        ("producer_evidence_json", evidence_json),
        ("producer_logical_cid", edge[3]),
        ("producer_output_port", edge[2]),
        ("producer_request_json", dispatch_json),
        ("producer_subject_json", subject_json),
        ("run_definition_cid", edge[0]),
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
  let binding = match
    @remote.prepare_remote_input_binding(body, max_binding_bytes) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  match retained_task_input_current(producer, transfer_record, current) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok({ producer, transfer_record, physical, binding, })
}

///|
/// Restore against the re-admitted original Run and recovered owner records.
/// Canonical equality checks every port, occurrence and Transfer field. No
/// reservation is created here; recovery must retain the journal's existing
/// destination holding and the source's independent cleanup responsibility.
pub fn admit_client_retained_task_input(
  saved : @remote.RemoteInputBinding,
  producer : ClientRetainedInputProducer,
  transfer_record : @transfer.RemoteTransferRecord,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  destination_use_id : String,
  current : ClientRetainedInputCurrent,
  max_binding_bytes : Int,
) -> Result[ClientRetainedTaskInput, ClientRetainedTaskInputIssue] {
  let value = match
    prepare_client_retained_task_input(
      producer, transfer_record, receipt, destination_use_id, current, max_binding_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @remote.remote_input_binding_cid(saved) !=
    @remote.remote_input_binding_cid(value.binding) ||
    @remote.remote_input_binding_body(saved) !=
    @remote.remote_input_binding_body(value.binding) {
    return Err(InvalidBinding)
  }
  Ok(value)
}

///|
pub fn client_retained_task_input_binding(
  value : ClientRetainedTaskInput,
) -> @remote.RemoteInputBinding {
  value.binding
}

///|
pub fn validate_client_retained_task_input_current(
  value : ClientRetainedTaskInput,
  current : ClientRetainedInputCurrent,
) -> Result[Unit, ClientRetainedTaskInputIssue] {
  retained_task_input_current(value.producer, value.transfer_record, current)
}

///|
pub fn client_retained_task_input_physical(
  value : ClientRetainedTaskInput,
) -> ClientTransferInput {
  value.physical
}

///|
pub fn client_retained_task_input_producer(
  value : ClientRetainedTaskInput,
) -> ClientRetainedInputProducer {
  value.producer
}

///|
pub(all) enum ClientRetainedTaskDispatchIssue {
  Input(ClientRetainedTaskInputIssue)
  Edge(ClientRetainedInputIssue)
  ForeignConsumer
  Dispatch(ClientTaskDispatchIssue)
}

///|
/// Issue a dependent dispatch only from a current owned retained input for
/// this exact checked edge. The durable Coordinator still owns the start
/// claim and must save the complete envelope before sending it.
pub fn prepare_client_retained_task_dispatch(
  prepared : PreparedClientProgram,
  compilation : ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
  task : Int,
  task_attempt : Int,
  dispatch_id : String,
  selected : ClientValuesSiteSelection,
  input : ClientRetainedTaskInput,
  current : ClientRetainedInputCurrent,
) -> Result[@remote.DispatchRequest, ClientRetainedTaskDispatchIssue] {
  match validate_client_retained_task_input_current(input, current) {
    Ok(_) => ()
    Err(issue) => return Err(Input(issue))
  }
  let graph = prepared_client_graph(prepared)
  // This first profile owns one checked incoming edge, never a fabricated
  // aggregate binding for multiple inputs.
  if @strategy.graph_task_input_count(graph, task) != Some(1) {
    return Err(ForeignConsumer)
  }
  let edge = match
    prepare_client_retained_input_edge(
      prepared, compilation, admission, definition, task, 0,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Edge(issue))
  }
  if client_retained_input_edge_projection(edge) !=
    client_retained_input_edge_projection(input.producer.edge) ||
    client_retained_input_edge_schema_cid(edge) !=
    client_retained_input_edge_schema_cid(input.producer.edge) {
    return Err(ForeignConsumer)
  }
  let scope = @remote.dispatch_request_execution_scope(
    client_retained_input_producer_dispatch(input.producer),
  )
  if selected.site_key != scope[0] ||
    selected.site_generation.to_string() != scope[1] ||
    !(current.site_binding_current)(
      selected.site_key,
      selected.site_generation.to_string(),
      selected.runtime_bundle_cid,
    ) ||
    client_request_authority_scope_cid(request) != (current.authority)() {
    return Err(ForeignConsumer)
  }
  let dispatch = match
    client_task_dispatch_with_input(
      prepared,
      compilation,
      admission,
      definition,
      request,
      task,
      task_attempt,
      dispatch_id,
      selected,
      () => Ok(input.binding),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  match validate_client_retained_task_input_current(input, current) {
    Ok(_) => Ok(dispatch)
    Err(issue) => Err(Input(issue))
  }
}

///|
pub fn client_retained_task_input_transfer_record(
  value : ClientRetainedTaskInput,
) -> @transfer.RemoteTransferRecord {
  value.transfer_record
}
