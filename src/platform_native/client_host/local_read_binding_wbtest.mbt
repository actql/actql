///|
let local_read_original_wire : String =
  #|{"version":"actql-config/0.1","native":{"result_read":{"enabled":true,"principal":"operator","connection":"cli","result_names":["answer"],"formats":["jsonl"],"purpose":"inspection","sink":"stdout","data_policy_cids":["sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],"max_bytes":65536,"max_uses":1,"expires_at":"2026-10-12T00:00:00.000Z"}}}

///|
test "Native finite read selection preserves exact values and refuses malformed ceilings" {
  let value = admit_native_local_read_selection(
    local_read_original_wire.replace_all(
      old="\"purpose\":\"inspection\"",
      new="\"purpose\":\"e\\u0301\\r\\n\"",
    ),
  ).unwrap()
  assert_eq(value.purpose, "e\u0301\r\n")
  assert_true(value.enabled())
  assert_eq(value.max_bytes, 65536)
  assert_eq(value.max_uses, 1)
  for
    (old, replacement, expected) in [
      ("\"max_bytes\":65536", "\"max_bytes\":0", InvalidLimits),
      ("\"max_bytes\":65536", "\"max_bytes\":536870913", InvalidLimits),
      ("\"max_uses\":1", "\"max_uses\":1025", InvalidLimits),
      ("\"sink\":\"stdout\"", "\"sink\":\"network\"", UnsupportedSink),
      ("\"formats\":[\"jsonl\"]", "\"formats\":[\"xml\"]", UnsupportedFormat),
      ("2026-10-12T00:00:00.000Z", "2026-02-30T00:00:00.000Z", InvalidOriginal),
    ] {
    match
      admit_native_local_read_selection(
        local_read_original_wire.replace_all(old~, new=replacement),
      ) {
      Err(issue) => assert_eq(issue, expected)
      Ok(_) => fail("invalid finite read selection accepted")
    }
  }
}

///|
test "Native read binding rechecks original selected file current scope and independent permissions" {
  let name = "local-read-policy-binding"
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(root).unwrap()
  let file = name + ".read.json"
  let writer = parent.create_writer(name + ".read.stage", 65536L).unwrap()
  writer.append(@utf8.encode(local_read_original_wire)).unwrap()
  writer.seal(file).unwrap() |> ignore
  let host = policy_host_fixture(name, files=[file])
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (original, _, _, definition) = journal_test_run(
    "read-request",
    "read-run",
    scope~,
  )
  let binding = host
    .bind_result_read_policy(crypto, file, "operator", "cli")
    .unwrap()
  assert_eq(binding.file.body, @utf8.encode(local_read_original_wire))
  assert_true(
    host.bind_result_read_policy(
      crypto, "unselected.read.json", "operator", "cli",
    )
    is Err(SelectionMismatch),
  )
  assert_true(
    host.bind_result_read_policy(crypto, file, "other", "cli")
    is Err(SelectionMismatch),
  )
  let facts : @result_access.NativeResultReadFacts = {
    request: {
      namespace_id: "original-namespace",
      authority_scope_cid: scope,
      run_definition_cid: @publication.publication_contract_identity(definition),
      principal_id: "operator",
      purpose: "inspection",
      result_name: "answer",
      format: "jsonl",
      attempt_id: "explicit-read",
    },
    public_index_entry_cid: "sha256:" + "b".repeat(64),
    result_manifest_cid: "sha256:" + "c".repeat(64),
    result_artifact_cid: "sha256:" + "d".repeat(64),
    result_definition_cid: "sha256:" + "e".repeat(64),
    material_generation_cid: "sha256:" + "f".repeat(64),
    observed_at: "2026-10-11T00:00:00.000Z",
  }
  assert_true(binding.require_request(original, facts) is Ok(_))
  for
    foreign in [
      { ..facts.request, purpose: "different-purpose", },
      { ..facts.request, format: "csv", },
      { ..facts.request, result_name: "unselected-result", },
    ] {
    assert_true(
      binding.require_request(original, { ..facts, request: foreign, })
      is Err(SelectionMismatch),
    )
  }
  assert_true(
    binding.require_request(original, {
      ..facts,
      request: { ..facts.request, principal_id: "other", },
    })
    is Err(AuthorizationDenied),
  )
  assert_true(
    binding.require_request(original, {
      ..facts,
      observed_at: "2026-10-12T00:00:00.000Z",
    })
    is Err(PolicyExpired),
  )
  assert_true(
    binding.require_request(original, { ..facts, observed_at: "invalid", })
    is Err(InvalidObservationTime),
  )
  // Even identical replacement bytes have a different physical generation.
  let generation = parent.inspect_generation(file).unwrap().unwrap()
  parent.reclaim_generation(file, generation).unwrap()
  let writer = parent
    .create_writer(name + ".replacement.stage", 65536L)
    .unwrap()
  writer.append(@utf8.encode(local_read_original_wire)).unwrap()
  writer.seal(file).unwrap() |> ignore
  assert_true(binding.require_request(original, facts) is Err(Adoption(_)))
  host.close().unwrap()
}

///|
test "Native read binding never substitutes submit or Result read for both current permissions" {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(root).unwrap()
  for (suffix, denied_resource) in [("run", "run"), ("result", "result/answer")] {
    let name = "local-read-denied-" + suffix
    let file = name + ".read.json"
    let writer = parent.create_writer(name + ".read.stage", 65536L).unwrap()
    writer.append(@utf8.encode(local_read_original_wire)).unwrap()
    writer.seal(file).unwrap() |> ignore
    let account_body = @utf8.encode(
      (
        #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"explicit-operations","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run","result/answer"]},"operation":{"any_of":["submit","read"]},"exclusions":[{"principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["\#(denied_resource)"]},"operation":{"any_of":["read"]}}]}]}
      ),
    )
    let host = policy_host_fixture(name, files=[file], account_body~)
    let crypto = epoch_test_crypto()
    let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
    let (original, _, _, definition) = journal_test_run(
      "read-request",
      "read-run",
      scope~,
    )
    let binding = host
      .bind_result_read_policy(crypto, file, "operator", "cli")
      .unwrap()
    assert_true(
      host.authorize({
        principal: "operator",
        connection: "cli",
        resource: "run",
        operation: "submit",
      })
      is Ok(@authorization.Allow(_)),
    )
    let facts : @result_access.NativeResultReadFacts = {
      request: {
        namespace_id: "original-namespace",
        authority_scope_cid: scope,
        run_definition_cid: @publication.publication_contract_identity(
          definition,
        ),
        principal_id: "operator",
        purpose: "inspection",
        result_name: "answer",
        format: "jsonl",
        attempt_id: "explicit-read",
      },
      public_index_entry_cid: "sha256:" + "b".repeat(64),
      result_manifest_cid: "sha256:" + "c".repeat(64),
      result_artifact_cid: "sha256:" + "d".repeat(64),
      result_definition_cid: "sha256:" + "e".repeat(64),
      material_generation_cid: "sha256:" + "f".repeat(64),
      observed_at: "2026-10-11T00:00:00.000Z",
    }
    assert_true(
      binding.require_request(original, facts)
      is Err(Journal(AuthorizationDenied)),
    )
    host.close().unwrap()
  }
}
