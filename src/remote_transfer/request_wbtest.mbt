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
fn transfer_request(
  route : RemoteTransferRoute,
  physical? : @manifest.PhysicalManifest = transfer_manifest(),
) -> RemoteTransferRequest {
  prepare_request(
    "coordinator-a",
    "transfer-1",
    route,
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
  assert_eq(request_journal_identity(direct), request_journal_identity(store))
}

///|
test "Transfer occurrence identity excludes content but binds destination" {
  let direct = transfer_request(DirectStream)
  let changed_route = transfer_request(TransferStore)
  assert_eq(
    request_journal_identity(direct),
    request_journal_identity(changed_route),
  )
  let changed_destination = prepare_request(
    "coordinator-a",
    "transfer-1",
    DirectStream,
    "source-a",
    4,
    "destination-c",
    9,
    "material-source-1",
    transfer_manifest(),
    16L,
    2000000000000L,
    transfer_cid("4"),
    transfer_cid("5"),
    transfer_cid("6"),
  ).unwrap()
  assert_not_eq(
    request_journal_identity(direct),
    request_journal_identity(changed_destination),
  )
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
  assert_eq(request_schema_contract_cid(restored), transfer_cid("1"))
  assert_eq(request_view_contract_cid(restored), transfer_cid("2"))
  assert_eq(request_codec_contract_cid(restored), transfer_cid("3"))
  assert_eq(request_row_count(restored), 2)
  assert_true(request_active_at(restored, 1999999999999L))
  assert_false(request_active_at(restored, 2000000000000L))
}

///|
test "Transfer Request isolates input aliases and rechecks every exposed chunk value" {
  for route in [DirectStream, TransferStore] {
    let physical = transfer_manifest()
    let request = transfer_request(route, physical~)
    let original_body = request_json(request).unwrap()
    let original_manifest_body = request_manifest_json(request).unwrap()
    let incoming = physical.chunks[0]
    physical.chunks[0] = { ..incoming, byte_length: 6L, }
    assert_eq(request_json(request), Ok(original_body))
    let exposed = request_manifest(request)
    let first = exposed.chunks[0]
    let second = exposed.chunks[1]
    for
      changed in [
        { ..first, cid: transfer_cid("f"), },
        { ..first, byte_length: 6L, },
        { ..first, row_count: 0, },
      ] {
      exposed.chunks[0] = changed
      assert_true(request_json(request) is Err(InvalidTransfer))
      assert_true(request_journal_identity(request) is Err(InvalidTransfer))
      assert_true(request_manifest_json(request) is Err(InvalidTransfer))
    }
    exposed.chunks[0] = second
    exposed.chunks[1] = first
    assert_true(request_json(request) is Err(InvalidTransfer))
    exposed.chunks[0] = first
    exposed.chunks[1] = second
    exposed.chunks.push(second)
    assert_true(request_json(request) is Err(InvalidTransfer))
    exposed.chunks.pop() |> ignore
    exposed.chunks.pop() |> ignore
    assert_true(request_json(request) is Err(InvalidTransfer))
    exposed.chunks.push(second)
    assert_eq(request_json(request), Ok(original_body))
    assert_eq(request_manifest_json(request), Ok(original_manifest_body))
  }
}

///|
test "Transfer decoder retains exact original contract bindings" {
  for route in [DirectStream, TransferStore] {
    let request = transfer_request(route)
    let body = request_json(request).unwrap()
    let manifest_body = request_manifest_json(request).unwrap()
    let manifest_cid = request_manifest(request).manifest_cid
    for
      (field, original) in [
        ("schema_contract_cid", request_schema_contract_cid(request)),
        ("view_contract_cid", request_view_contract_cid(request)),
        ("codec_contract_cid", request_codec_contract_cid(request)),
        ("physical_manifest_cid", manifest_cid),
      ] {
      let changed = body.replace(
        old="\"" + field + "\":\"" + original + "\"",
        new="\"" + field + "\":\"" + transfer_cid("f") + "\"",
      )
      assert_not_eq(changed, body)
      assert_true(
        admit_request_json(
          changed,
          manifest_body,
          request_cid(request),
          manifest_cid,
          2,
          4096,
          12L,
        )
        is Err(InvalidTransfer),
      )
    }
  }
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
