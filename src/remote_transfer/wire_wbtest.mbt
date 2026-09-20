///|
test "Transfer admission envelope is canonical and jointly admitted" {
  let request = transfer_request(DirectStream)
  let body = transfer_admission_envelope_json(request).unwrap()
  let admitted = admit_transfer_admission_envelope_json(
    body,
    request_cid(request),
    transfer_manifest().manifest_cid,
    2,
    4096,
    12L,
  ).unwrap()
  assert_eq(request_json(admitted), request_json(request))
  assert_eq(transfer_admission_envelope_json(admitted), Ok(body))
  assert_true(
    admit_transfer_admission_envelope_json(
      body + " ",
      request_cid(request),
      transfer_manifest().manifest_cid,
      2,
      4096,
      12L,
    )
    is Err(InvalidTransfer),
  )
}

///|
test "Transfer response state is emitted and re-admitted by common control" {
  let request = transfer_request(DirectStream)
  let record = open_record(request)
  ignore(apply(prepare_start(record).unwrap()))
  let body = remote_transfer_reply_json(record).unwrap()
  let admitted = admit_remote_transfer_reply_json(body, request).unwrap()
  assert_eq(record_projection(admitted), record_projection(record))
  assert_true(
    admit_remote_transfer_reply_json(
      body.replace(old="\"requestCid\":\"", new="\"requestCid\":\"x"),
      request,
    )
    is Err(TransferIdentityMismatch),
  )
  assert_true(
    admit_remote_transfer_reply_json(body + " ", request)
    is Err(InvalidTransfer),
  )
}
