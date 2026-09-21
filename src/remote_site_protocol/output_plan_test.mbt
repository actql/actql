///|
fn output_plan_subject(
  output : RemotePollOutput,
  payload_request : @payload.PublicationPayloadRequest,
  transfer_request : @transfer.RemoteTransferRequest,
) -> RemoteManagedOutputSubject {
  let manifest = @transfer.request_manifest(transfer_request)
  let request = remote_poll_output_request(output)
  prepare_remote_managed_output_subject(
    dispatch_request_identity(request),
    @payload.publication_payload_material_identity(payload_request),
    remote_output_holding_evidence_cid(
      request,
      @payload.publication_payload_material_identity(payload_request),
      manifest.referenced_bytes,
    ).unwrap(),
    cid("acacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacac"),
    manifest.schema_contract_cid,
    manifest.view_contract_cid,
    manifest.codec_contract_cid,
    @manifest.manifest_cid(manifest),
    cid("adadadadadadadadadadadadadadadadadadadadadadadadadadadadadadadad"),
    manifest.row_count,
    manifest.referenced_bytes,
  ).unwrap()
}

///|
test "output plan carries exact requests without executing output" {
  let (output, payload_request, transfer_request, _) = output_result_fixture()
  let subject = output_plan_subject(output, payload_request, transfer_request)
  let plan = prepare_remote_output_plan(
    output, subject, payload_request, transfer_request,
  ).unwrap()
  let body = remote_output_plan_json(plan).unwrap()
  let admitted = admit_remote_output_plan_json(
    body, output, subject, 8, 4096, 1048576L,
  ).unwrap()
  assert_eq(remote_output_plan_json(admitted), Ok(body))
  assert_eq(
    @payload.publication_payload_request_identity(
      remote_output_plan_payload_request(admitted),
    ),
    @payload.publication_payload_request_identity(payload_request),
  )
  assert_eq(
    @transfer.request_cid(remote_output_plan_transfer_request(admitted)),
    @transfer.request_cid(transfer_request),
  )
}

///|
test "output plan rejects manifest substitution and foreign subjects" {
  let (output, payload_request, transfer_request, _) = output_result_fixture()
  let subject = output_plan_subject(output, payload_request, transfer_request)
  let plan = prepare_remote_output_plan(
    output, subject, payload_request, transfer_request,
  ).unwrap()
  let body = remote_output_plan_json(plan).unwrap()
  assert_true(
    admit_remote_output_plan_json(
      body.replace(old="12", new="13"),
      output,
      subject,
      8,
      4096,
      1048576L,
    )
    is Err(InvalidDispatch),
  )
  let foreign = prepare_remote_managed_output_subject(
    dispatch_request_identity(remote_poll_output_request(output)),
    @payload.publication_payload_material_identity(payload_request),
    remote_output_holding_evidence_cid(
      remote_poll_output_request(output),
      @payload.publication_payload_material_identity(payload_request),
      12L,
    ).unwrap(),
    cid("acacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacac"),
    cid("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
    @payload.publication_payload_request_logical_relation(payload_request),
    @payload.publication_payload_request_codec(payload_request),
    @manifest.manifest_cid(@transfer.request_manifest(transfer_request)),
    cid("adadadadadadadadadadadadadadadadadadadadadadadadadadadadadadadad"),
    2,
    12L,
  ).unwrap()
  assert_true(
    admit_remote_output_plan_json(body, output, foreign, 8, 4096, 1048576L)
    is Err(InvalidDispatch),
  )
}
