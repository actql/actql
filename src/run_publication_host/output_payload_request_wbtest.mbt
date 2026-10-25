///|
test "portable payload intent requires original live EOF Result custody" {
  let parent = retry_export()
  let (run, invocation, retention) = storage_binding_context()
  let cid = fn(ch : String) { "sha256:" + ch.repeat(64) }
  let prepare = fn(limit : Int64) {
    parent.prepare_payload_request(cid("a"), cid("b"), cid("c"), limit)
  }
  assert_true(prepare(100000L) is Err(InvalidState))
  while parent.next().unwrap() is Some(_) {

  }
  parent.finish().unwrap() |> ignore
  assert_true(prepare(100000L) is Err(InvalidState))
  parent
  .issue_result_evidence(
    cid("1"),
    [cid("2")],
    @publication.publication_contract_identity(run),
    cid("4"),
    cid("5"),
    100000,
    10000,
    100,
  )
  .unwrap()
  parent.issue_artifact(invocation, retention, 100000, 10000, 100).unwrap()
  |> ignore
  // Independent exact payload is [{"id":1},{"id":2}]: 19 UTF-8 bytes, 2 rows.
  assert_true(prepare(18L) is Err(PayloadLimit))
  let request = prepare(19L).unwrap()
  assert_eq(@payload.publication_payload_request_max_bytes(request), 19L)
  assert_eq(@payload.publication_payload_request_row_count(request), 2L)
  assert_eq(@payload.publication_payload_request_attempt(request), cid("a"))
  assert_eq(
    @payload.publication_payload_request_store_authority(request),
    cid("b"),
  )
  assert_eq(@payload.publication_payload_material_identity(request), cid("c"))
  assert_eq(
    @payload.publication_payload_request_schema(request),
    "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
  )
  assert_eq(
    @payload.publication_payload_request_codec(request),
    "sha256:5a95e60847276d02229eba9550dd9808a8a8c2764decd4dad667954f020db7cc",
  )
  let before = @payload.publication_payload_request_json(request).unwrap()
  let snapshot = parent.start_captured_snapshot(100000, 10000, 100).unwrap()
  assert_eq(snapshot.advance(1).unwrap(), (false, 1))
  snapshot.cancel()
  assert_eq(
    @payload.publication_payload_request_json(prepare(19L).unwrap()).unwrap(),
    before,
  )
  parent.cancel()
  assert_true(prepare(19L) is Err(InvalidState))
}
