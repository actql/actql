///|
fn payload_replay_fixture() -> (
  PublicationOutputExport,
  @payload.PublicationPayloadRequest,
) {
  let parent = retry_export()
  let (run, invocation, retention) = storage_binding_context()
  let cid = fn(ch : String) { "sha256:" + ch.repeat(64) }
  while parent.next().unwrap() is Some(_) {

  }
  parent.finish().unwrap() |> ignore
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
  (
    parent,
    parent.prepare_payload_request(cid("a"), cid("b"), cid("c"), 19L).unwrap(),
  )
}

///|
test "portable payload replay returns independent exact bytes from the original Result" {
  let (parent, request) = payload_replay_fixture()
  let replay = parent.replay_payload_request(request).unwrap()
  let bytes = StringBuilder()
  while replay.next().unwrap() is Some(chunk) {
    bytes.write_string(chunk)
  }
  bytes.write_string(replay.finish().unwrap())
  assert_eq(bytes.to_string(), "[{\"id\":1},{\"id\":2}]")
  assert_eq(@payload.publication_payload_request_max_bytes(request), 19L)
  assert_eq(@payload.publication_payload_request_row_count(request), 2L)
  assert_true(replay.next() is Err(InvalidState))
  parent.cancel()
}

///|
test "portable payload replay cancellation preserves original Receipt and repeated replay" {
  let (parent, request) = payload_replay_fixture()
  let original = @payload.publication_payload_request_json(request).unwrap()
  let receipt = parent.receipt.unwrap()
  let artifact = parent.artifact.unwrap()
  let child = parent.replay_payload_request(request).unwrap()
  assert_true(child.next().unwrap() is Some(_))
  child.cancel()
  child.cancel()
  assert_true(child.next() is Err(InvalidState))
  assert_true(physical_equal(parent.receipt.unwrap(), receipt))
  assert_true(@execution.completed_relation_export_receipt_live(receipt))
  assert_true(physical_equal(parent.artifact.unwrap(), artifact))
  let retry = parent.replay_payload_request(request).unwrap()
  let bytes = StringBuilder()
  while retry.next().unwrap() is Some(chunk) {
    bytes.write_string(chunk)
  }
  bytes.write_string(retry.finish().unwrap())
  assert_eq(bytes.to_string(), "[{\"id\":1},{\"id\":2}]")
  assert_eq(
    @payload.publication_payload_request_json(request).unwrap(),
    original,
  )
  assert_eq(
    @payload.publication_payload_request_json(
      parent
      .prepare_payload_request(
        @payload.publication_payload_request_attempt(request),
        @payload.publication_payload_request_store_authority(request),
        @payload.publication_payload_material_identity(request),
        19L,
      )
      .unwrap(),
    ).unwrap(),
    original,
  )
  parent.cancel()
  assert_true(parent.replay_payload_request(request) is Err(InvalidState))
}

///|
test "portable payload replay refuses substituted Result bindings before opening bytes" {
  let (parent, request) = payload_replay_fixture()
  let originals = [
    @payload.publication_payload_request_result_definition(request),
    @payload.publication_payload_request_logical_relation(request),
    @payload.publication_payload_request_schema(request),
    @payload.publication_payload_request_ordering_evidence(request),
    @payload.publication_payload_request_codec(request),
  ]
  for changed in 0..<7 {
    let fields = originals.copy()
    if changed < 5 {
      fields[changed] = "sha256:" + "f".repeat(64)
    }
    let wrong = @payload.prepare_publication_payload_request(
      @payload.publication_payload_request_store_authority(request),
      @payload.publication_payload_request_attempt(request),
      @payload.publication_payload_material_identity(request),
      fields[0],
      fields[1],
      fields[2],
      fields[3],
      fields[4],
      if changed == 5 {
        20L
      } else {
        19L
      },
      if changed == 6 {
        3L
      } else {
        2L
      },
    ).unwrap()
    assert_true(parent.replay_payload_request(wrong) is Err(RequestMismatch))
  }
  let child = parent.replay_payload_request(request).unwrap()
  child.cancel()
  parent.cancel()
}
