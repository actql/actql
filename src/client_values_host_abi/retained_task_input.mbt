///|
/// A replayable binding and ports to current existing owners. The first
/// successful Transfer snapshot is never retained as permanent authority.
pub struct ClientValuesHostRetainedTaskInput {
  producer : @host.ClientRetainedInputProducer
  saved : @remote.RemoteInputBinding
  read_transfer : () -> String
  receipt_wire : String
  receipt_cid : String
  destination_use_id : String
  current : @host.ClientRetainedInputCurrent
  max_chunks : Int
  max_manifest_bytes : Int
  max_referenced_bytes : Int64
  max_binding_bytes : Int
}

///|
fn client_host_retained_transfer(
  value : ClientValuesHostRetainedTaskInput,
) -> Result[@host.ClientRetainedTaskInput, @host.ClientRetainedTaskInputIssue] {
  let durable = match
    @transfer.admit_durable_remote_transfer_record(
      @utf8.encode((value.read_transfer)()),
      value.max_chunks,
      value.max_manifest_bytes,
      value.max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(@host.ForeignTransfer)
  }
  let record = match @transfer.restore_durable_remote_transfer_record(durable) {
    Ok(value) => value
    Err(_) => return Err(@host.ForeignTransfer)
  }
  let receipt = match
    @transfer.admit_destination_receipt_json(
      value.receipt_wire,
      @transfer.record_request(record),
      value.receipt_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(@host.ForeignTransfer)
  }
  @host.admit_client_retained_task_input(
    value.saved,
    value.producer,
    record,
    receipt,
    value.destination_use_id,
    value.current,
    value.max_binding_bytes,
  )
}

///|
/// Current ports must query the trusted Host/Site/Transfer owners. A receipt
/// is admitted evidence, not physical payload access or a borrower claim.
#export_name("clientValuesHostPrepareRetainedTaskInput")
pub fn client_values_host_prepare_retained_task_input(
  producer : @host.ClientRetainedInputProducer,
  read_transfer : () -> String,
  receipt_wire : String,
  receipt_cid : String,
  destination_use_id : String,
  site_current : (String, String, String) -> Bool,
  authority : () -> String,
  now_unix_ms : () -> Int64,
  authorized : (String, String) -> Bool,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
  max_binding_bytes : Int,
) -> Result[
  ClientValuesHostRetainedTaskInput,
  @host.ClientRetainedTaskInputIssue,
] {
  let current = @host.install_client_retained_input_owner_current(
    site_current,
    authority,
    now_unix_ms,
    (producer, request) => {
      match @transfer.request_json(request) {
        Ok(wire) =>
          authorized(
            @remote.dispatch_request_identity(
              @host.client_retained_input_producer_dispatch(producer),
            ),
            wire,
          )
        Err(_) => false
      }
    },
  )
  let durable = match
    @transfer.admit_durable_remote_transfer_record(
      @utf8.encode(read_transfer()),
      max_chunks,
      max_manifest_bytes,
      max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(@host.ForeignTransfer)
  }
  let record = match @transfer.restore_durable_remote_transfer_record(durable) {
    Ok(value) => value
    Err(_) => return Err(@host.ForeignTransfer)
  }
  let receipt = match
    @transfer.admit_destination_receipt_json(
      receipt_wire,
      @transfer.record_request(record),
      receipt_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(@host.ForeignTransfer)
  }
  let input = match
    @host.prepare_client_retained_task_input(
      producer, record, receipt, destination_use_id, current, max_binding_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let value = {
    producer,
    saved: @host.client_retained_task_input_binding(input),
    read_transfer,
    receipt_wire,
    receipt_cid,
    destination_use_id,
    current,
    max_chunks,
    max_manifest_bytes,
    max_referenced_bytes,
    max_binding_bytes,
  }
  // Detect a replaced/reclaimed destination across the initial handoff too.
  client_host_retained_transfer(value).map(_ => value)
}

///|
/// Reconstruct a saved binding only after current custody has been restored.
/// No reservation or borrow is created by admission.
#export_name("clientValuesHostAdmitRetainedTaskInput")
pub fn client_values_host_admit_retained_task_input(
  value : ClientValuesHostRetainedTaskInput,
  saved_wire : String,
  saved_cid : String,
) -> Result[
  ClientValuesHostRetainedTaskInput,
  @host.ClientRetainedTaskInputIssue,
] {
  if @remote.remote_input_binding_body(value.saved) != saved_wire ||
    @remote.remote_input_binding_cid(value.saved) != saved_cid {
    return Err(@host.InvalidBinding)
  }
  client_host_retained_transfer(value).map(_ => value)
}

///|
#export_name("clientValuesHostValidateRetainedTaskInput")
pub fn client_values_host_validate_retained_task_input(
  value : ClientValuesHostRetainedTaskInput,
) -> Result[Unit, @host.ClientRetainedTaskInputIssue] {
  client_host_retained_transfer(value).map(_ => ())
}

///|
/// Historical binding wire is not authorization or a borrow/start claim.
#export_name("clientValuesHostRetainedTaskInputFacts")
pub fn client_values_host_retained_task_input_facts(
  value : ClientValuesHostRetainedTaskInput,
) -> Array[String] {
  [
    @remote.remote_input_binding_cid(value.saved),
    @remote.remote_input_binding_body(value.saved),
  ]
}

///|
#export_name("clientValuesHostPrepareRetainedTaskDispatch")
pub fn client_values_host_prepare_retained_task_dispatch(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientTaskCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
  task : Int,
  task_attempt : Int,
  dispatch_id : String,
  site_key : String,
  site_generation : Int,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  obligations_cid : String,
  budget_cid : String,
  evidence_issuer_capability_cid : String,
  grant_cid : String,
  value : ClientValuesHostRetainedTaskInput,
) -> Result[@remote.DispatchRequest, @host.ClientRetainedTaskDispatchIssue] {
  let input = match client_host_retained_transfer(value) {
    Ok(value) => value
    Err(issue) => return Err(@host.Input(issue))
  }
  let dispatch = match
    @host.prepare_client_retained_task_dispatch(
      prepared,
      compilation,
      admission,
      definition,
      request,
      task,
      task_attempt,
      dispatch_id,
      {
        site_key,
        site_generation,
        runtime_bundle_cid,
        connector_registration,
        connector_revision,
        strategy_revision,
        obligations_cid,
        budget_cid,
        evidence_issuer_capability_cid,
        grant_cid,
      },
      input,
      value.current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Re-read the destination owner after all trusted authorization callbacks.
  match client_host_retained_transfer(value) {
    Ok(_) => Ok(dispatch)
    Err(issue) => Err(@host.Input(issue))
  }
}
