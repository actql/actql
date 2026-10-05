///|
/// Connector-owned meaning for one standard Remote dispatch input backed by
/// an exact committed Transfer destination. The destination receipt and use
/// identify the physical provider independently of the selected route.
struct NativeRemoteStandardTransferInput {
  binding : @remote.RemoteInputBinding
  request : @transfer.RemoteTransferRequest
  destination_use_id : String
  destination_receipt_cid : String
}

///|
pub(all) enum NativeRemoteStandardTransferInputIssue {
  InvalidInput
  Limit
  Transfer(@transfer.RemoteTransferIssue)
}

///|
fn native_transfer_input_issue(
  issue : @publication_host.ClientTransferInputIssue,
) -> NativeRemoteStandardTransferInputIssue {
  match issue {
    @publication_host.InvalidInput => InvalidInput
    @publication_host.Limit => Limit
    @publication_host.Transfer(value) => Transfer(value)
  }
}

///|
fn native_transfer_input(
  value : @publication_host.ClientTransferInput,
) -> NativeRemoteStandardTransferInput {
  {
    binding: @publication_host.client_transfer_binding(value),
    request: @publication_host.client_transfer_request(value),
    destination_use_id: @publication_host.client_transfer_destination_use_id(
      value,
    ),
    destination_receipt_cid: @publication_host.client_transfer_destination_receipt_cid(
      value,
    ),
  }
}

///|
pub fn prepare_native_remote_standard_transfer_input(
  request : @transfer.RemoteTransferRequest,
  destination_use_id : String,
  destination_receipt_cid : String,
  max_binding_bytes : Int,
) -> Result[
  NativeRemoteStandardTransferInput,
  NativeRemoteStandardTransferInputIssue,
] {
  @publication_host.prepare_client_transfer_input(
    request, destination_use_id, destination_receipt_cid, max_binding_bytes,
  )
  .map(native_transfer_input)
  .map_err(native_transfer_input_issue)
}

///|
pub fn admit_native_remote_standard_transfer_input(
  binding : @remote.RemoteInputBinding,
  max_binding_bytes : Int,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[
  NativeRemoteStandardTransferInput,
  NativeRemoteStandardTransferInputIssue,
] {
  @publication_host.admit_client_transfer_input(
    binding, max_binding_bytes, max_chunks, max_manifest_bytes, max_referenced_bytes,
  )
  .map(native_transfer_input)
  .map_err(native_transfer_input_issue)
}

///|
pub fn native_remote_standard_transfer_binding(
  input : NativeRemoteStandardTransferInput,
) -> @remote.RemoteInputBinding {
  input.binding
}

///|
pub fn native_remote_standard_transfer_request(
  input : NativeRemoteStandardTransferInput,
) -> @transfer.RemoteTransferRequest {
  input.request
}

///|
pub fn native_remote_standard_transfer_destination_use_id(
  input : NativeRemoteStandardTransferInput,
) -> String {
  input.destination_use_id
}

///|
pub fn native_remote_standard_transfer_destination_receipt_cid(
  input : NativeRemoteStandardTransferInput,
) -> String {
  input.destination_receipt_cid
}
