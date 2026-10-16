///|
test "original Result inventory refuses foreign custody and retains empty publication as unknown" {
  let name = "original-result-manifest"
  let host = observed_state_host_fixture(name, true)
  let crypto = epoch_test_crypto()
  let (_, request, definition) = original_selection_fixture(
    host, "result-manifest-original", "result-manifest-run",
  )
  let original = host.lookup_submitted_run_original_by_id(
    crypto, "operator", "cli", "result-manifest-run",
  ).unwrap()
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(base).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  parent.create_directory(name + "-foreign").unwrap() |> ignore
  let library = local_journal_test_library()
  let store = @publication_store.open_store(
    library, base + "/" + name, "sha256:" + "c".repeat(64),
    65536L, 8L, 131072L,
  ).unwrap()
  let foreign = @publication_store.open_store(
    library, base + "/" + name + "-foreign", "sha256:" + "c".repeat(64),
    65536L, 8L, 131072L,
  ).unwrap()
  assert_true(
    host.lookup_original_result_names_json(
      crypto, "operator", "cli", original, store, "local-test",
    ) is Err(ForeignRun),
  )
  host.bind_run_publisher(
    crypto, "operator", "cli", request, definition, name + ".run.json", store,
  ).unwrap() |> ignore
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  assert_eq(
    host.lookup_original_result_names_json(
      crypto, "operator", "cli", original, store, "local-test",
    ).unwrap(),
    None,
  )
  assert_true(
    host.lookup_original_result_names_json(
      crypto, "operator", "cli", original, foreign, "local-test",
    ) is Err(ForeignRun),
  )
  assert_true(
    host.lookup_original_result_names_json(
      crypto, "operator", "cli", original, store, "other-namespace",
    ) is Err(ForeignRun),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
  host.close().unwrap()
  let no_current = host.lookup_original_result_names_json(
    crypto, "operator", "cli", original, store, "local-test",
  )
  assert_true(store.close().unwrap())
  assert_true(foreign.close().unwrap())
  assert_true(no_current is Err(AuthorizationDenied))
}
