///|
/// Host-installed access to current trusted owners. None of these values is
/// reconstructed from the saved input body. Authorization must cover the
/// original Run/edge and both current Transfer grants; this port issues no
/// grant and is not an execution capability.
pub struct NativeRemoteRetainedInputCurrent {
  site : () -> @site.ExecutionSite
  authority : () -> String
  now_unix_ms : () -> Int64
  authorized : (
    @publication_host.ClientRetainedInputProducer,
    @transfer.RemoteTransferRequest,
  ) -> Bool
}

///|
pub fn install_native_remote_retained_input_current(
  site : () -> @site.ExecutionSite,
  authority : () -> String,
  now_unix_ms : () -> Int64,
  authorized : (
    @publication_host.ClientRetainedInputProducer,
    @transfer.RemoteTransferRequest,
  ) -> Bool,
) -> NativeRemoteRetainedInputCurrent {
  { site, authority, now_unix_ms, authorized, }
}

///|
/// A checked consumer edge joined to the original durable producer and an
/// independently committed Transfer destination. The bytes are replayable
/// evidence, not a borrow, start claim or proof of physical cleanup.
pub struct NativeRemoteRetainedTaskInput {
  producer : @publication_host.ClientRetainedInputProducer
  transfer_record : @transfer.RemoteTransferRecord
  physical : NativeRemoteStandardTransferInput
  binding : @remote.RemoteInputBinding
}

///|
pub(all) enum NativeRemoteRetainedTaskInputIssue {
  ProducerUnavailable
  ForeignTransfer
  TransferNotCommitted
  StaleSiteGeneration
  ForeignAuthority
  AuthorizationUnavailable
  TransferExpired
  InputMaterialUnavailable
  InvalidBinding
  Encoding
}

///|
fn retained_task_input_current(
  producer : @publication_host.ClientRetainedInputProducer,
  transfer_record : @transfer.RemoteTransferRecord,
  current : NativeRemoteRetainedInputCurrent,
) -> Result[Unit, NativeRemoteRetainedTaskInputIssue] {
  if !@publication_host.client_retained_input_producer_available(producer) {
    return Err(ProducerUnavailable)
  }
  let current_site = (current.site)()
  let current_authority = (current.authority)()
  let dispatch = @publication_host.client_retained_input_producer_dispatch(
    producer,
  )
  let scope = @remote.dispatch_request_execution_scope(dispatch)
  let request = @transfer.record_request(transfer_record)
  let facts = @transfer.request_projection(request)
  if scope[0] != @site.site_key(current_site) ||
    scope[1] != @site.site_generation(current_site).to_string() ||
    !@site.site_binding_current(
      current_site,
      @site.site_generation(current_site),
      scope[2],
    ) ||
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
    @publication_host.client_retained_input_producer_subject(producer),
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
pub fn prepare_native_remote_retained_task_input(
  producer : @publication_host.ClientRetainedInputProducer,
  transfer_record : @transfer.RemoteTransferRecord,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  destination_use_id : String,
  current : NativeRemoteRetainedInputCurrent,
  max_binding_bytes : Int,
) -> Result[NativeRemoteRetainedTaskInput, NativeRemoteRetainedTaskInputIssue] {
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
    prepare_native_remote_standard_transfer_input(
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
      @publication_host.client_retained_input_producer_dispatch(producer),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let evidence_json = match
    @remote.remote_execution_evidence_json(
      @publication_host.client_retained_input_producer_evidence(producer),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let subject_json = match
    @remote.remote_managed_output_subject_json(
      @publication_host.client_retained_input_producer_subject(producer),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let edge = @publication_host.client_retained_input_edge_projection(
    @publication_host.client_retained_input_producer_edge(producer),
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
pub fn admit_native_remote_retained_task_input(
  saved : @remote.RemoteInputBinding,
  producer : @publication_host.ClientRetainedInputProducer,
  transfer_record : @transfer.RemoteTransferRecord,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  destination_use_id : String,
  current : NativeRemoteRetainedInputCurrent,
  max_binding_bytes : Int,
) -> Result[NativeRemoteRetainedTaskInput, NativeRemoteRetainedTaskInputIssue] {
  let value = match
    prepare_native_remote_retained_task_input(
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
pub fn native_remote_retained_task_input_binding(
  value : NativeRemoteRetainedTaskInput,
) -> @remote.RemoteInputBinding {
  value.binding
}

///|
/// Confirm an existing physical reader before attaching it to the consumer.
/// Failure leaves the caller's reader/holding owner intact for cleanup retry.
/// Passing this check grants neither execution nor source reacquisition.
pub fn validate_native_remote_retained_task_input_borrow(
  value : NativeRemoteRetainedTaskInput,
  material : @transfer_client.NativeRemoteDestinationMaterialUse,
  current : NativeRemoteRetainedInputCurrent,
) -> Result[Unit, NativeRemoteRetainedTaskInputIssue] {
  match
    retained_task_input_current(value.producer, value.transfer_record, current) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if @transfer_client.destination_material_use_receipt_cid(material) !=
    value.physical.destination_receipt_cid ||
    @transfer_client.destination_material_use_id(material) !=
    value.physical.destination_use_id {
    return Err(ForeignTransfer)
  }
  if !@transfer_client.destination_material_use_available(material) {
    return Err(InputMaterialUnavailable)
  }
  // Physical validation may race with cancellation, expiry or revocation.
  // Recheck the trusted owners after it without freeing any reader on failure.
  retained_task_input_current(value.producer, value.transfer_record, current)
}
