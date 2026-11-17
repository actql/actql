///|
test "public index geometry measures the actual sealed issuer including its identity" {
  let fixture = commit_read_fixture()
  let originals = fixture.originals
  let (attempt, _) = observed_commit_test_pair(fixture)
  let bindings = [originals[13]]
  let at = "2026-09-17T00:00:02.000Z"
  let geometry = public_index_entry_construction_geometry(
    originals[0],
    originals[1],
    originals[2],
    originals[3],
    originals[4],
    bindings,
    originals[5],
    attempt,
    at,
    65536,
    4096,
    32,
  ).unwrap()
  let issued = issue_public_index_entry(
    originals[0],
    originals[1],
    originals[2],
    originals[3],
    originals[4],
    bindings,
    originals[5],
    attempt,
    at,
    geometry.bytes,
    geometry.nodes,
    geometry.depth,
  ).unwrap()
  assert_eq(
    @utf8.encode(publication_contract_json(issued)).length(),
    geometry.bytes,
  )
  assert_eq(geometry.fields, 13)
  assert_eq(geometry.objects, 1)
  assert_eq(geometry.arrays, 1)
  // One object, thirteen value fields (one array), and one binding item.
  assert_eq(geometry.nodes, 15)
  assert_true(
    public_index_entry_construction_geometry(
      originals[0],
      originals[1],
      originals[2],
      originals[3],
      originals[4],
      bindings,
      originals[5],
      attempt,
      at,
      geometry.bytes - 1,
      geometry.nodes,
      geometry.depth,
    )
    is Err(CommitIssuanceEncoding),
  )
  assert_true(
    public_index_entry_construction_geometry(
      originals[0],
      originals[1],
      originals[2],
      originals[3],
      originals[4],
      bindings,
      originals[5],
      attempt,
      at,
      geometry.bytes,
      geometry.nodes - 1,
      geometry.depth,
    )
    is Err(CommitIssuanceEncoding),
  )
  assert_true(
    public_index_entry_construction_geometry(
      originals[0],
      originals[1],
      originals[2],
      originals[3],
      originals[4],
      bindings,
      originals[5],
      attempt,
      at,
      geometry.bytes,
      geometry.nodes,
      geometry.depth - 1,
    )
    is Err(CommitIssuanceEncoding),
  )
  let (retained, workspace) = publication_wire_construction_inventory(geometry).unwrap()
  assert_true(retained.record_headers > 0L && retained.owned_utf16_units > 0L)
  assert_true(workspace.record_headers > retained.record_headers)
  assert_true(workspace.owned_wire_bytes >= geometry.bytes.to_int64())
  fixture.preparation.cancel()
}

///|
test "public index measurement preserves nominal mismatches and binding occurrence refusals" {
  let fixture = commit_read_fixture()
  let o = fixture.originals
  let (attempt, _) = observed_commit_test_pair(fixture)
  let at = "2026-09-17T00:00:02.000Z"
  assert_true(
    public_index_entry_construction_geometry(
      o[1],
      o[1],
      o[2],
      o[3],
      o[4],
      [o[13]],
      o[5],
      attempt,
      at,
      65536,
      4096,
      32,
    )
    is Err(CommitIssuanceWrongContract),
  )
  assert_true(
    public_index_entry_construction_geometry(
      o[0],
      o[1],
      o[2],
      o[3],
      o[4],
      [o[13], o[13]],
      o[5],
      attempt,
      at,
      65536,
      4096,
      32,
    )
    is Err(CommitIssuanceInventoryMismatch),
  )
  let other_request = issue_publication_request(
    o[0],
    [o[8]],
    "namespace-雪\"\\",
    ordering_test_cid("3"),
    ordering_test_cid("4"),
    ordering_test_cid("5"),
    "2026-09-17T00:00:00.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  let other_attempt = issue_publication_attempt(
    other_request,
    o[0],
    "other-attempt",
    ordering_test_cid("6"),
    None,
    "2026-09-17T00:00:01.000Z",
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(
    public_index_entry_construction_geometry(
      o[0],
      o[1],
      o[2],
      o[3],
      o[4],
      [o[13]],
      o[5],
      other_attempt,
      at,
      65536,
      4096,
      32,
    )
    is Err(CommitIssuanceReferenceMismatch("attempt.publication_request_cid")),
  )
  let geometry = public_index_entry_construction_geometry(
    o[0],
    o[1],
    o[2],
    o[3],
    o[4],
    [o[13]],
    other_request,
    other_attempt,
    at,
    65536,
    4096,
    32,
  ).unwrap()
  let issued = issue_public_index_entry(
    o[0],
    o[1],
    o[2],
    o[3],
    o[4],
    [o[13]],
    other_request,
    other_attempt,
    at,
    65536,
    4096,
    32,
  ).unwrap()
  assert_eq(
    @utf8.encode(publication_contract_json(issued)).length(),
    geometry.bytes,
  )
  fixture.preparation.cancel()
}
