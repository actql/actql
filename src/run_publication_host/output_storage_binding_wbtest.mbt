///|
fn storage_binding_context() -> (
  @publication.PublicationContract,
  @publication.PublicationContract,
  @publication.PublicationContract,
) {
  let cid = fn(ch : String) { "sha256:" + ch.repeat(64) }
  let run = @publication.seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\",\"scope_id\":\"scope\",\"run_id\":\"run\",\"compiled_plan_cid\":\"" +
    cid("1") +
    "\",\"invocation_template_cid\":\"" +
    cid("6") +
    "\",\"authorization_context_cid\":\"" +
    cid("2") +
    "\",\"input_artifact_set_cid\":\"" +
    cid("3") +
    "\",\"created_at\":\"2026-09-18T00:00:00.000Z\",\"valid_until\":\"2099-01-01T00:00:00.000Z\"}",
    100000,
    10000,
    100,
  ).unwrap()
  let invocation = @publication.seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\",\"invocation_template_cid\":\"" +
    cid("6") +
    "\",\"observation_set_cid\":\"" +
    cid("7") +
    "\"}",
    100000,
    10000,
    100,
  ).unwrap()
  let retention = @publication.seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"" +
    cid("8") +
    "\",\"effective_data_policy_cid\":\"" +
    cid("4") +
    "\",\"available_until\":\"2099-01-01T00:00:00.000Z\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2099-01-03T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"" +
    cid("9") +
    "\",\"metadata_delete_by\":\"2099-01-04T00:00:00.000Z\",\"clock_contract_cid\":\"" +
    cid("a") +
    "\"}",
    100000,
    10000,
    100,
  ).unwrap()
  (run, invocation, retention)
}

///|
test "portable Result binding requires original EOF evidence and physical identity" {
  let parent = retry_export()
  let (run, invocation, retention) = storage_binding_context()
  // Independent SHA256 of the fixed UTF-8 payload [{"id":1},{"id":2}].
  let digest = "7dcee6a0c50483d0fb68d53b37822d55409a37928ffa228c6b9a482e3373e770"
  let bind = fn(bytes : Int, hash : String, max_bytes : Int) {
    parent.issue_durable_binding(
      run,
      invocation,
      retention,
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      bytes,
      hash,
      max_bytes,
      10000,
      100,
    )
  }
  assert_true(bind(19, digest, 100000) is Err(InvalidState))
  while parent.next().unwrap() is Some(_) {

  }
  parent.finish().unwrap() |> ignore
  assert_true(bind(19, digest, 100000) is Err(InvalidState))
  parent
  .issue_result_evidence(
    "sha256:" + "1".repeat(64),
    ["sha256:" + "2".repeat(64)],
    @publication.publication_contract_identity(run),
    "sha256:" + "4".repeat(64),
    "sha256:" + "5".repeat(64),
    100000,
    10000,
    100,
  )
  .unwrap()
  parent.issue_artifact(invocation, retention, 100000, 10000, 100).unwrap()
  |> ignore
  assert_true(bind(18, digest, 100000) is Err(Output(ForeignMaterial)))
  assert_true(bind(19, "0".repeat(64), 100000) is Err(Output(ForeignMaterial)))
  assert_true(
    parent.issue_durable_binding(
      run,
      run,
      retention,
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      19,
      digest,
      100000,
      10000,
      100,
    )
    is Err(
      DurableBinding(@publication.DurableBindingWrongContract("run_invocation"))
    ),
  )
  assert_true(bind(19, digest, 1) is Err(DurableBinding(_)))
  let binding = bind(19, digest, 100000).unwrap()
  let wire = @publication.publication_contract_json(binding)
  assert_eq(
    parent.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  // Independently hashed schema; semantic expected bytes are fixed above.
  assert_true(
    wire.contains(
      "\"result_schema_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\"",
    ),
  )
  assert_true(wire.contains("\"byte_count\":19"))
  assert_true(wire.contains("\"row_count\":2"))
  assert_true(wire.contains("\"result_fields\":[\"id\"]"))
  assert_true(wire.contains("\"physical_sha256\":\"" + digest + "\""))
  assert_true(
    wire.contains(
      "\"codec_contract_cid\":\"sha256:5a95e60847276d02229eba9550dd9808a8a8c2764decd4dad667954f020db7cc\"",
    ),
  )
  let snapshot = parent.start_captured_snapshot(100000, 10000, 100).unwrap()
  assert_eq(snapshot.advance(1).unwrap(), (false, 1))
  snapshot.cancel()
  assert_eq(
    @publication.publication_contract_json(bind(19, digest, 100000).unwrap()),
    wire,
  )
  // Borrowed snapshot cleanup leaves the original binding facts live. Parent
  // cleanup revokes them; an old content hash cannot revive the original loan.
  parent.cancel()
  assert_true(bind(19, digest, 100000) is Err(InvalidState))
}
