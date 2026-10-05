///|
pub struct NativeRemoteRetainedInputCurrent {
  common : @publication_host.ClientRetainedInputCurrent
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
  {
    common: @publication_host.install_client_retained_input_current(
      site, authority, now_unix_ms, authorized,
    ),
  }
}

///|
pub struct NativeRemoteRetainedTaskInput {
  common : @publication_host.ClientRetainedTaskInput
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
  InputMaterial(@transfer_client.NativeRemoteTransferClientIssue)
  InvalidBinding
  Encoding
}

///|
fn native_retained_task_input_issue(
  issue : @publication_host.ClientRetainedTaskInputIssue,
) -> NativeRemoteRetainedTaskInputIssue {
  match issue {
    @publication_host.ProducerUnavailable => ProducerUnavailable
    @publication_host.ForeignTransfer => ForeignTransfer
    @publication_host.TransferNotCommitted => TransferNotCommitted
    @publication_host.StaleSiteGeneration => StaleSiteGeneration
    @publication_host.ForeignAuthority => ForeignAuthority
    @publication_host.AuthorizationUnavailable => AuthorizationUnavailable
    @publication_host.TransferExpired => TransferExpired
    @publication_host.InvalidBinding => InvalidBinding
    @publication_host.Encoding => Encoding
  }
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
  let common = match
    @publication_host.prepare_client_retained_task_input(
      producer,
      transfer_record,
      receipt,
      destination_use_id,
      current.common,
      max_binding_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(native_retained_task_input_issue(issue))
  }
  let physical = native_transfer_input(
    @publication_host.client_retained_task_input_physical(common),
  )
  Ok({
    common,
    physical,
    binding: @publication_host.client_retained_task_input_binding(common),
  })
}

///|
/// Re-admit the saved body against the recovered producer, Transfer and
/// current trusted Site owners. This creates no holding or reservation.
pub fn admit_native_remote_retained_task_input(
  saved : @remote.RemoteInputBinding,
  producer : @publication_host.ClientRetainedInputProducer,
  transfer_record : @transfer.RemoteTransferRecord,
  receipt : @transfer.RemoteTransferDestinationReceipt,
  destination_use_id : String,
  current : NativeRemoteRetainedInputCurrent,
  max_binding_bytes : Int,
) -> Result[NativeRemoteRetainedTaskInput, NativeRemoteRetainedTaskInputIssue] {
  let common = match
    @publication_host.admit_client_retained_task_input(
      saved,
      producer,
      transfer_record,
      receipt,
      destination_use_id,
      current.common,
      max_binding_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(native_retained_task_input_issue(issue))
  }
  let physical = native_transfer_input(
    @publication_host.client_retained_task_input_physical(common),
  )
  Ok({
    common,
    physical,
    binding: @publication_host.client_retained_task_input_binding(common),
  })
}

///|
pub fn native_remote_retained_task_input_binding(
  value : NativeRemoteRetainedTaskInput,
) -> @remote.RemoteInputBinding {
  value.binding
}

///|
fn native_retained_task_input_current(
  value : NativeRemoteRetainedTaskInput,
  current : NativeRemoteRetainedInputCurrent,
) -> Result[Unit, NativeRemoteRetainedTaskInputIssue] {
  @publication_host.validate_client_retained_task_input_current(
    value.common,
    current.common,
  ).map_err(native_retained_task_input_issue)
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
  match native_retained_task_input_current(value, current) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if @transfer_client.destination_material_use_receipt_cid(material) !=
    value.physical.destination_receipt_cid ||
    @transfer_client.destination_material_use_id(material) !=
    value.physical.destination_use_id {
    return Err(ForeignTransfer)
  }
  match @transfer_client.validate_destination_material_use(material) {
    Ok(_) => ()
    Err(issue) => return Err(InputMaterial(issue))
  }
  // Physical validation may race with cancellation, expiry or revocation.
  // Recheck the trusted owners after it without freeing any reader on failure.
  native_retained_task_input_current(value, current)
}
