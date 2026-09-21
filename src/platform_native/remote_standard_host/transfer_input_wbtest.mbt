///|
fn standard_transfer_input_cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
fn standard_transfer_input_request() -> @transfer.RemoteTransferRequest {
  let chunk = b"{\"id\":3}"
  let manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    standard_transfer_input_cid("1"),
    standard_transfer_input_cid("2"),
    standard_transfer_input_cid("3"),
    1,
    ["sha256:" + @sha.hex(chunk)],
    [chunk.length().to_int64()],
    [1],
    8,
    4096,
    chunk.length().to_int64(),
  ).unwrap()
  @transfer.prepare_request(
    "coordinator-a",
    "transfer-a",
    @transfer.TransferStore,
    "source-a",
    1,
    "destination-a",
    2,
    "material-a",
    manifest,
    chunk.length().to_int64(),
    4102444800000L,
    standard_transfer_input_cid("4"),
    standard_transfer_input_cid("5"),
    standard_transfer_input_cid("6"),
  ).unwrap()
}

///|
test "standard Transfer input binds exact request and destination receipt" {
  let request = standard_transfer_input_request()
  let receipt = @transfer.prepare_destination_receipt(
    request,
    standard_transfer_input_cid("7"),
  ).unwrap()
  let receipt_cid = @transfer.destination_receipt_cid(receipt)
  let prepared = prepare_native_remote_standard_transfer_input(
    request, "destination-use-a", receipt_cid, 262144,
  ).unwrap()
  let binding = native_remote_standard_transfer_binding(prepared)
  let admitted = admit_native_remote_standard_transfer_input(
    binding, 262144, 8, 65536, 1048576L,
  ).unwrap()
  assert_eq(
    @transfer.request_cid(native_remote_standard_transfer_request(admitted)),
    @transfer.request_cid(request),
  )
  assert_eq(
    native_remote_standard_transfer_destination_use_id(admitted),
    "destination-use-a",
  )
  assert_eq(
    native_remote_standard_transfer_destination_receipt_cid(admitted),
    receipt_cid,
  )
  let foreign = prepare_native_remote_standard_transfer_input(
    request, "destination-use-b", receipt_cid, 262144,
  ).unwrap()
  assert_false(
    @remote.remote_input_binding_cid(
      native_remote_standard_transfer_binding(foreign),
    ) ==
    @remote.remote_input_binding_cid(binding),
  )
}
