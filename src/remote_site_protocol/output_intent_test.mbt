///|
fn output_intent_projection(
  route? : @transfer.RemoteTransferRoute = @transfer.DirectStream,
) -> RemoteOutputIntentProjection {
  {
    store_authority_cid: cid(
      "5555555555555555555555555555555555555555555555555555555555555555",
    ),
    publication_attempt_cid: cid(
      "6666666666666666666666666666666666666666666666666666666666666666",
    ),
    result_definition_cid: cid(
      "7777777777777777777777777777777777777777777777777777777777777777",
    ),
    ordering_evidence_cid: cid(
      "8888888888888888888888888888888888888888888888888888888888888888",
    ),
    coordinator_authority: "coordinator-a",
    transfer_attempt: "transfer-a",
    transfer_route: route,
    destination_site_key: "site-b",
    destination_site_generation: 2,
    transfer_max_bytes: 1048576L,
    transfer_expires_unix_ms: 2000000000000L,
    source_grant_cid: cid(
      "9999999999999999999999999999999999999999999999999999999999999999",
    ),
    destination_grant_cid: cid(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    ),
    route_capability_cid: cid(
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    ),
    transfer_origin: "https://transfer.example.invalid/object-a",
  }
}

///|
test "output intent is canonical and bound to the exact dispatch" {
  let request = coordinator_request("dispatch-output", 41)
  let intent = prepare_remote_output_intent(request, output_intent_projection()).unwrap()
  let body = remote_output_intent_json(intent).unwrap()
  let admitted = admit_remote_output_intent_json(
    body,
    remote_output_intent_identity(intent),
    request,
  ).unwrap()
  assert_true(remote_output_intent_matches_dispatch(admitted, request))
  assert_eq(remote_output_intent_json(admitted), Ok(body))
  assert_true(
    admit_remote_output_intent_json(
      body,
      remote_output_intent_identity(intent),
      coordinator_request("dispatch-other", 42),
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_output_intent_json(
      body.replace(old="site-b", new="site-c"),
      remote_output_intent_identity(intent),
      request,
    )
    is Err(InvalidDispatch),
  )
}

///|
test "output intent rejects invalid capacity and route identity" {
  let request = coordinator_request("dispatch-output-invalid", 43)
  let invalid = { ..output_intent_projection(), transfer_max_bytes: 0L, }
  assert_true(
    prepare_remote_output_intent(request, invalid) is Err(InvalidDispatch),
  )
  let store = prepare_remote_output_intent(
    request,
    output_intent_projection(route=@transfer.TransferStore),
  ).unwrap()
  let body = remote_output_intent_json(store).unwrap()
  assert_true(body.contains("\"transfer_route\":\"store\""))
  assert_true(
    admit_remote_output_intent_json(
      body.replace(old="\"store\"", new="\"direct\""),
      remote_output_intent_identity(store),
      request,
    )
    is Err(InvalidDispatch),
  )
}
