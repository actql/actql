///|
// Physical Native cases are compiled here but require an explicitly selected
// Native execution fixture. Missing fixture environment is never a skip/pass.
test "Native Result Policy selection refuses foreign Store and facts without grant or revision mutation" {
  let host = policy_host_fixture("local-result-policy-binding")
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, prepared, compiled, definition) = journal_test_run(
    "policy-request",
    "policy-run",
    scope~,
  )
  let journal = host.run_journal().unwrap()
  let original = journal
    .bind_run(request, prepared, compiled, definition, true)
    .unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let name = "local-result-policy-store"
  let parent = @filesystem.open_private_root(root).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  let store = @publication_store.open_store(
    local_journal_test_library(),
    root + "/" + name,
    "sha256:" + "a".repeat(64),
    256L,
    8L,
    65536L,
  ).unwrap()
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
  assert_true(
    host.resolve_result_policy_original(
      crypto, "operator", "cli", request, store, facts,
    )
    is Err(ForeignRun),
  )
  let foreign = {
    ..facts,
    request: { ..facts.request, principal_id: "other", },
  }
  assert_true(
    host.resolve_result_policy_original(
      crypto, "operator", "cli", request, store, foreign,
    )
    is Err(AuthorizationDenied),
  )
  let foreign = {
    ..facts,
    request: {
      ..facts.request,
      run_definition_cid: "sha256:" + "f".repeat(64),
    },
  }
  assert_true(
    host.resolve_result_policy_original(
      crypto, "operator", "cli", request, store, foreign,
    )
    is Err(ForeignRun),
  )
  // Installing an original Store binding is a separate setup mutation. The
  // subsequent read-only resolution cannot turn absent publication into data.
  let (authority, device, inode) = store.custody_location().unwrap()
  let binding = installed_publication_binding(
    facts.request.namespace_id,
    authority,
    device,
    inode,
  ).unwrap()
  journal.bind_publication(request, binding, () => true).unwrap()
  guard journal.lookup(request, true) is Ok(Retained(bound)) else {
    fail("original Run missing")
  }
  assert_eq(bound.revision, original.revision + 1L)
  assert_true(
    host.resolve_result_policy_original(
      crypto, "operator", "cli", request, store, facts,
    )
    is Err(PublicationObservation(@publication_store.DeliveryAttemptUnresolved)),
  )
  guard journal.lookup(request, true) is Ok(Retained(after)) else {
    fail("original Run missing after lookup")
  }
  assert_eq(after.revision, bound.revision)
  assert_false(after.dispatch_reserved)
  assert_false(after.physical_start_claimed)
  assert_eq(after.publication_policy_originals, None)
  assert_true(store.close().unwrap())
  host.close().unwrap()
}
