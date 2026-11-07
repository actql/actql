///|
// Report only the original API phase and typed issue kind. A setup refusal
// retires the same acquired Host/Stores; a missing close ACK stays pending.
fn[T, E] result_manifest_checked(
  host : NativeLocalHostConnection,
  stores : Array[@publication_store.Store],
  value : Result[T, E],
  phase : String,
  kind : (E) -> String,
) -> T raise {
  match value {
    Ok(value) => value
    Err(issue) => {
      let issue_kind = kind(issue)
      let host_cleanup = if host.close() is Ok(_) {
        "confirmed"
      } else {
        "pending"
      }
      let mut stores_confirmed = true
      for store in stores {
        if !(store.close() is Ok(true)) {
          stores_confirmed = false
        }
      }
      fail(
        "original Result inventory phase=" +
        phase +
        " kind=" +
        issue_kind +
        " host_cleanup=" +
        host_cleanup +
        " stores_cleanup=" +
        (if stores_confirmed { "confirmed" } else { "pending" }),
      )
    }
  }
}

///|
fn result_manifest_publisher_kind(
  issue : NativeLocalPublisherBindingIssue,
) -> String {
  match issue {
    Adoption(_) => "Adoption"
    Journal(issue) => original_selection_journal_kind(issue)
    InvalidOriginal => "InvalidOriginal"
    SelectionMismatch => "SelectionMismatch"
    OriginalOperation(_, _) => "OriginalOperation"
    AuthorizationDenied => "AuthorizationDenied"
  }
}

///|
test "original Result inventory refuses foreign custody and retains empty publication as unknown" {
  let name = "original-result-manifest"
  let host = observed_state_host_fixture(name, true)
  let crypto = epoch_test_crypto()
  let (_, request, definition) = original_selection_fixture(
    host, "result-manifest-original", "result-manifest-run",
  )
  let original = host
    .lookup_submitted_run_original_by_id(
      crypto, "operator", "cli", "result-manifest-run",
    )
    .unwrap()
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(base).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  parent.create_directory(name + "-foreign").unwrap() |> ignore
  let library = local_journal_test_library()
  let store = @publication_store.open_store(
    library,
    base + "/" + name,
    "sha256:" + "c".repeat(64),
    65536L,
    8L,
    131072L,
  ).unwrap()
  let foreign = @publication_store.open_store(
    library,
    base + "/" + name + "-foreign",
    "sha256:" + "c".repeat(64),
    65536L,
    8L,
    131072L,
  ).unwrap()
  assert_true(
    host.lookup_original_result_names_json(
      crypto, "operator", "cli", original, store, "local-test",
    )
    is Err(ForeignRun),
  )
  // Binding a publisher does not install a missing journal/Store original.
  // Retain the original setup refusal as an explicit counterexample.
  assert_true(
    host.bind_run_publisher(
      crypto,
      "operator",
      "cli",
      request,
      definition,
      name + ".run.json",
      store,
    )
    is Err(Journal(CustodyLost)),
  )
  let publication = result_manifest_checked(
    host,
    [store, foreign],
    install_native_client_cancellation_publication(
      store, "local-test", 65536, 8192, 64,
    ),
    "install_cancellation_publication",
    original_selection_journal_kind,
  )
  result_manifest_checked(
    host,
    [store, foreign],
    host.journal.bind_installed_publication(request, publication, () => {
      host.authorize({
        principal: "operator",
        connection: "cli",
        resource: "run",
        operation: "publish",
      })
      is Ok(Allow(_))
    }),
    "bind_installed_publication",
    original_selection_journal_kind,
  )
  |> ignore
  result_manifest_checked(
    host,
    [store, foreign],
    host.bind_run_publisher(
      crypto,
      "operator",
      "cli",
      request,
      definition,
      name + ".run.json",
      store,
    ),
    "bind_run_publisher",
    result_manifest_publisher_kind,
  )
  |> ignore
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  assert_eq(
    host
    .lookup_original_result_names_json(
      crypto, "operator", "cli", original, store, "local-test",
    )
    .unwrap(),
    None,
  )
  assert_true(
    host.lookup_original_result_names_json(
      crypto, "operator", "cli", original, foreign, "local-test",
    )
    is Err(ForeignRun),
  )
  assert_true(
    host.lookup_original_result_names_json(
      crypto, "operator", "cli", original, store, "other-namespace",
    )
    is Err(ForeignRun),
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
