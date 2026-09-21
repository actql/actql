///|
fn output_result_fixture() -> (
  RemotePollOutput,
  @payload.PublicationPayloadRequest,
  @transfer.RemoteTransferRequest,
  @transfer.RemoteTransferRecord,
) {
  let request = coordinator_request("dispatch-output-result", 51)
  let intent = prepare_remote_output_intent(
    request,
    output_intent_projection(route=@transfer.DirectStream),
  ).unwrap()
  let material = cid(
    "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  )
  let manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    cid("1111111111111111111111111111111111111111111111111111111111111111"),
    cid("2222222222222222222222222222222222222222222222222222222222222222"),
    cid("3333333333333333333333333333333333333333333333333333333333333333"),
    2,
    [cid("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd")],
    [12L],
    [2],
    4,
    4096,
    12L,
  ).unwrap()
  let projection = remote_output_intent_projection(intent)
  let payload_request = @payload.prepare_publication_payload_request(
    projection.store_authority_cid,
    projection.publication_attempt_cid,
    material,
    projection.result_definition_cid,
    manifest.view_contract_cid,
    manifest.schema_contract_cid,
    projection.ordering_evidence_cid,
    manifest.codec_contract_cid,
    12L,
    2L,
  ).unwrap()
  let transfer_request = @transfer.prepare_request(
    projection.coordinator_authority,
    projection.transfer_attempt,
    projection.transfer_route,
    "site-a",
    1,
    projection.destination_site_key,
    projection.destination_site_generation,
    material,
    manifest,
    projection.transfer_max_bytes,
    projection.transfer_expires_unix_ms,
    projection.source_grant_cid,
    projection.destination_grant_cid,
    projection.route_capability_cid,
  ).unwrap()
  let record = @transfer.open_record(transfer_request)
  ignore(
    @transfer.commit_transition(@transfer.prepare_start(record).unwrap(), true).unwrap(),
  )
  ignore(
    @transfer.commit_transition(
      @transfer.prepare_source_settled(record, true, false).unwrap(),
      true,
    ).unwrap(),
  )
  ignore(
    @transfer.commit_transition(
      @transfer.prepare_destination_commit(record).unwrap(),
      true,
    ).unwrap(),
  )
  let output = admit_remote_poll_output_json(
    remote_poll_output_json(request, intent).unwrap(),
  ).unwrap()
  (output, payload_request, transfer_request, record)
}

///|
test "output result binds the sealed payload and committed Transfer" {
  let (output, payload_request, transfer_request, transfer_record) = output_result_fixture()
  let digest = cid(
    "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
  )
  let result = prepare_remote_output_result(
    output, payload_request, digest, transfer_record,
  ).unwrap()
  let body = remote_output_result_json(result).unwrap()
  let admitted = admit_remote_output_result_json(
    body, output, payload_request, transfer_request,
  ).unwrap()
  assert_eq(remote_output_result_json(admitted), Ok(body))
  assert_eq(remote_output_result_payload_digest(admitted), digest)
  assert_true(
    @transfer.record_is_destination_committed(
      remote_output_result_transfer_record(admitted, transfer_request).unwrap(),
    ),
  )
  assert_true(
    admit_remote_output_result_json(
      body.replace(
        old=@transfer.request_cid(transfer_request),
        new=cid(
          "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        ),
      ),
      output,
      payload_request,
      transfer_request,
    )
    is Err(InvalidDispatch),
  )
}

///|
test "output result rejects an uncommitted Transfer" {
  let (output, payload_request, transfer_request, _) = output_result_fixture()
  let uncommitted = @transfer.open_record(transfer_request)
  assert_true(
    prepare_remote_output_result(
      output,
      payload_request,
      cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
      uncommitted,
    )
    is Err(InvalidDispatch),
  )
}
