///|
fn transfer_cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
fn transfer_manifest() -> @manifest.PhysicalManifest {
  @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    transfer_cid("1"),
    transfer_cid("2"),
    transfer_cid("3"),
    2,
    [transfer_cid("a"), transfer_cid("b")],
    [5L, 7L],
    [1, 1],
    2,
    4096,
    12L,
  ).unwrap()
}

///|
fn transfer_request(route : RemoteTransferRoute) -> RemoteTransferRequest {
  prepare_request(
    "coordinator-a",
    "transfer-1",
    route,
    "source-a",
    4,
    "destination-b",
    9,
    "material-source-1",
    transfer_manifest(),
    16L,
    2000000000000L,
    transfer_cid("4"),
    transfer_cid("5"),
    transfer_cid("6"),
  ).unwrap()
}

///|
test "direct and Store routes have distinct stable identities" {
  let direct = transfer_request(DirectStream)
  let store = transfer_request(TransferStore)
  assert_eq(
    request_cid(direct),
    "sha256:d55289cdc96cffdeb8a98998e935455720799d3fc3b34e4c3267fb6f2e0c1f03",
  )
  assert_not_eq(request_cid(direct), request_cid(store))
  assert_true(request_json(direct).unwrap().contains("\"route\":\"direct\""))
  assert_true(request_json(store).unwrap().contains("\"route\":\"store\""))
  assert_eq(request_projection(direct)[8], "16")
}

///|
test "canonical request and manifest wire are re-admitted together" {
  let direct = transfer_request(DirectStream)
  let body = request_json(direct).unwrap()
  let manifest_body = request_manifest_json(direct).unwrap()
  let restored = admit_request_json(
    body,
    manifest_body,
    request_cid(direct),
    transfer_manifest().manifest_cid,
    2,
    4096,
    12L,
  ).unwrap()
  assert_eq(request_cid(restored), request_cid(direct))
  assert_eq(request_json(restored), Ok(body))
  assert_eq(request_manifest_json(restored), Ok(manifest_body))
  let store = transfer_request(TransferStore)
  assert_true(
    admit_request_json(
      body,
      manifest_body,
      request_cid(store),
      transfer_manifest().manifest_cid,
      2,
      4096,
      12L,
    )
    is Err(TransferIdentityMismatch),
  )
  assert_eq(request_chunk_cids(restored), [transfer_cid("a"), transfer_cid("b")])
  assert_eq(request_chunk_byte_lengths(restored), [5L, 7L])
  assert_eq(request_chunk_row_counts(restored), [1, 1])
  assert_true(request_active_at(restored, 1999999999999L))
  assert_false(request_active_at(restored, 2000000000000L))
}

///|
test "wire admission rejects noncanonical and mismatched bindings" {
  let request = transfer_request(DirectStream)
  let body = request_json(request).unwrap()
  let manifest_body = request_manifest_json(request).unwrap()
  let manifest_cid = transfer_manifest().manifest_cid
  assert_true(
    admit_request_json(
      body + " ",
      manifest_body,
      request_cid(request),
      manifest_cid,
      2,
      4096,
      12L,
    )
    is Err(InvalidTransfer),
  )
  assert_true(
    admit_request_json(
      body,
      manifest_body + " ",
      request_cid(request),
      manifest_cid,
      2,
      4096,
      12L,
    )
    is Err(InvalidTransfer),
  )
  assert_true(
    admit_request_json(
      body,
      manifest_body,
      request_cid(request),
      transfer_cid("f"),
      2,
      4096,
      12L,
    )
    is Err(InvalidTransfer),
  )
  assert_true(
    admit_request_json(
      body,
      manifest_body,
      request_cid(request),
      manifest_cid,
      1,
      4096,
      12L,
    )
    is Err(InvalidTransfer),
  )
}

///|
test "remote Transfer rejects insufficient capacity and forged manifests" {
  let physical = transfer_manifest()
  assert_true(
    prepare_request(
      "coordinator-a",
      "transfer-1",
      DirectStream,
      "source-a",
      4,
      "destination-b",
      9,
      "material-source-1",
      physical,
      11L,
      2000000000000L,
      transfer_cid("4"),
      transfer_cid("5"),
      transfer_cid("6"),
    )
    is Err(TransferCapacityExceeded),
  )
  let forged = { ..physical, manifest_cid: transfer_cid("f"), }
  assert_true(
    prepare_request(
      "coordinator-a",
      "transfer-1",
      DirectStream,
      "source-a",
      4,
      "destination-b",
      9,
      "material-source-1",
      forged,
      16L,
      2000000000000L,
      transfer_cid("4"),
      transfer_cid("5"),
      transfer_cid("6"),
    )
    is Err(InvalidTransfer),
  )
  assert_true(
    admit_request(
      "coordinator-a",
      "transfer-1",
      DirectStream,
      "source-a",
      4,
      "destination-b",
      9,
      "material-source-1",
      physical,
      16L,
      2000000000000L,
      transfer_cid("4"),
      transfer_cid("5"),
      transfer_cid("6"),
      transfer_cid("f"),
    )
    is Err(TransferIdentityMismatch),
  )
}
