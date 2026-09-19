///|
test "destination receipt binds exact request generation and grant" {
  let request = transfer_request(TransferStore)
  let receipt = prepare_destination_receipt(request, "destination-material-1").unwrap()
  let body = destination_receipt_json(receipt).unwrap()
  assert_eq(
    destination_receipt_cid(receipt),
    "sha256:8e11f292e35823133bcad1b761bc42a206a213ad937da0b3dbb45cbe66305289",
  )
  assert_eq(
    body, "{\"destination_grant_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"destination_material_generation\":\"destination-material-1\",\"destination_site_generation\":9,\"destination_site_key\":\"destination-b\",\"physical_manifest_cid\":\"sha256:20d34d82f48f00d7f73256c62f209ea05a2c0ea76f752d9ebe015bc61230d02f\",\"request_cid\":\"sha256:64d5384300c01675d0eecc43763bfc129d9ab623669c6bd7e6a664b996a63ed8\",\"version\":\"actql-remote-transfer-destination-receipt/0.1\"}",
  )
  let restored = admit_destination_receipt_json(
    body,
    request,
    destination_receipt_cid(receipt),
  ).unwrap()
  assert_eq(
    destination_receipt_projection(restored),
    destination_receipt_projection(receipt),
  )
  assert_true(
    body.contains(
      "\"version\":\"actql-remote-transfer-destination-receipt/0.1\"",
    ),
  )
}

///|
test "destination receipt rejects noncanonical and foreign evidence" {
  let request = transfer_request(TransferStore)
  let receipt = prepare_destination_receipt(request, "destination-material-1").unwrap()
  let body = destination_receipt_json(receipt).unwrap()
  assert_true(
    admit_destination_receipt_json(
      body + " ",
      request,
      destination_receipt_cid(receipt),
    )
    is Err(TransferIdentityMismatch),
  )
  assert_true(
    admit_destination_receipt_json(
      body,
      transfer_request(DirectStream),
      destination_receipt_cid(receipt),
    )
    is Err(TransferIdentityMismatch),
  )
  assert_true(
    admit_destination_receipt_json(body, request, transfer_cid("f"))
    is Err(TransferIdentityMismatch),
  )
}
