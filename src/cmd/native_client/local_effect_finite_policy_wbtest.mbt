///|
fn[T, E] effect_finite_cli_ok(value : Result[T, E], phase : String) -> T raise {
  match value {
    Ok(value) => value
    Err(_) => fail("Effect finite CLI fixture: " + phase)
  }
}

///|
// A real adopted Host/journal and the product's original finite selection.
// This fixture never starts Compute, creates a grant or accesses an old DB.
fn effect_finite_cli_host(
  name : String,
) -> (
  @local_host.NativeLocalHostConnection,
  LocalHostSettings,
  @local_crypto.Library,
  LocalRunInstallation,
  @local_sqlite.Library,
) raise {
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = base + "/" + name
  let sqlite_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let crypto_path = @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap()
  let parent = effect_finite_cli_ok(
    @local_filesystem.open_private_root(base),
    "parent",
  )
  effect_finite_cli_ok(parent.create_directory(name), "directory") |> ignore
  effect_finite_cli_ok(parent.close(), "parent.close")
  let originals = effect_finite_cli_ok(
    @run_host.client_local_product_finite_originals(
      root,
      sqlite_path,
      crypto_path,
      "2026-10-10T00:00:00.000Z",
      @run_host.client_local_product_assets(),
    ),
    "originals",
  )
  let names = [
    "profile.json", "read.json", "run.json", "retention.json", "store.json",
  ]
  let files = effect_finite_cli_ok(
    @local_filesystem.open_private_root(root),
    "files",
  )
  for file in ["account.json", ..names] {
    let body = originals.iter().find_first(pair => pair.0 == file).unwrap().1
    let writer = effect_finite_cli_ok(
      files.create_writer(file + ".stage", 65536L),
      "writer",
    )
    effect_finite_cli_ok(writer.append(body), "append")
    effect_finite_cli_ok(writer.seal(file), "seal") |> ignore
  }
  effect_finite_cli_ok(files.close(), "files.close")
  let crypto = effect_finite_cli_ok(
    @local_crypto.load_library(crypto_path),
    "crypto",
  )
  let sqlite = effect_finite_cli_ok(
    @local_sqlite.load_library(sqlite_path),
    "sqlite",
  )
  let host = effect_finite_cli_ok(
    effect_finite_cli_ok(
      @local_host.begin_native_local_host_adoption(
        root,
        "host",
        root,
        "account.json",
        "local-cli",
        crypto,
        configuration_files=names,
      ),
      "adoption",
    ).open_journal(sqlite, crypto, 100.0, 8, 8388608L),
    "journal",
  )
  let settings : LocalHostSettings = {
    account_file: "account.json",
    account_id: "local-cli",
    principal: "local-cli",
    connection: "local",
    state_parent: root,
    state_name: "host",
    managed_root: root,
    sqlite_library: sqlite_path,
    signature_library: crypto_path,
    ttl_ms: 100.0,
    record_limit: 8,
    snapshot_bytes: 8388608L,
    installation_files: names,
    source_file: None,
    run_file: Some("run.json"),
    read_file: Some("read.json"),
    run_policy_profile_file: Some("profile.json"),
    reviewer_file: None,
  }
  let wire = @utf8.decode(
    originals.iter().find_first(pair => pair.0 == "run.json").unwrap().1,
  ) catch {
    _ => fail("run.utf8")
  }
  (host, settings, crypto, local_run_installation(wire), sqlite)
}

///|
fn effect_finite_cli_submission(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  nonce : String,
) -> (
  @local_host.NativeClientSubmissionReference,
  @local_host.NativeClientSubmittedPreparation,
  String,
) raise {
  let scope = effect_finite_cli_ok(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
    "scope",
  )
  let epoch = effect_finite_cli_ok(host.epoch_authority(), "epoch.authority")
  let issued = effect_finite_cli_ok(
    epoch.issue_epoch(
      scope,
      local_submit_allowed(host, settings, crypto, scope),
      1791763200000.0,
    ),
    "epoch.issue",
  )
  let reference = effect_finite_cli_ok(
    @local_host.prepare_native_client_submission_reference(issued, nonce),
    "reference",
  )
  let intent = effect_finite_cli_ok(
    @run_host.prepare_client_submitted_intent(
      "{\"kind\":\"program\",\"input\":" +
      local_effect_prefix_fixture_document +
      ",\"parameters\":null}",
      65536,
      8192,
      64,
    ),
    "intent",
  )
  let journal = effect_finite_cli_ok(host.run_journal(), "journal.borrow")
  effect_finite_cli_ok(
    journal.record_submitted_intent(
      epoch,
      reference,
      intent,
      scope,
      local_submit_allowed(host, settings, crypto, scope),
      1791763200001.0,
    ),
    "intent.record",
  )
  |> ignore
  (reference, local_effect_prefix_fixture_preparation(), scope)
}

///|
test "CLI Effect finite prefix uses a fresh next-day Policy without accepting or starting a Run" {
  let (host, settings, crypto, installed, sqlite) = effect_finite_cli_host(
    "cli-effect-finite-fresh",
  )
  defer {
    host.close() |> ignore
    sqlite.close_checked() |> ignore
  }
  let (reference, preparation, scope) = effect_finite_cli_submission(
    host, settings, crypto, "fresh",
  )
  assert_eq(
    @publication.result_retention_interval_state(
      installed.retention,
      "2026-10-12T00:00:00.000Z",
    ),
    Ok("delete_due"),
  )
  let prepared = local_effect_prepare_start_with_clocks(
    host,
    settings,
    crypto,
    preparation,
    reference,
    installed,
    scope,
    () => "2026-10-12T00:00:00.000Z",
    () => 1791763200002.0,
  )
  guard prepared is Some(original) else { fail("expected new original") }
  let body = local_input_cursor(
    @publication.publication_contract_json(original.definition),
  )
  let object = @decode.open_object(body).unwrap()
  assert_eq(run_text(object, "created_at"), "2026-10-12T00:00:00.000Z")
  assert_eq(run_text(object, "valid_until"), "2026-10-13T00:00:00.000Z")
  let journal = host.run_journal().unwrap()
  guard journal.lookup_submitted_intent(
      host.epoch_authority().unwrap(),
      reference,
      scope,
      true,
      1791763200003.0,
    )
    is Ok(Submitted(saved)) else {
    fail("saved intent missing")
  }
  assert_true(@local_host.native_client_submitted_run_admission(saved) is None)
  assert_eq(
    @publication.result_retention_interval_state(
      installed.retention,
      "2026-10-12T00:00:00.000Z",
    ),
    Ok("delete_due"),
  )
  effect_finite_cli_ok(host.close(), "host.close")
  effect_finite_cli_ok(sqlite.close_checked(), "sqlite.close")
}

///|
test "CLI Effect finite prefix selects an accepted original before an invalid candidate time" {
  let (host, settings, crypto, installed, sqlite) = effect_finite_cli_host(
    "cli-effect-finite-accepted",
  )
  defer {
    host.close() |> ignore
    sqlite.close_checked() |> ignore
  }
  let (reference, preparation, scope) = effect_finite_cli_submission(
    host, settings, crypto, "accepted",
  )
  guard local_effect_prepare_start_with_clocks(
      host,
      settings,
      crypto,
      preparation,
      reference,
      installed,
      scope,
      () => "2026-10-12T00:00:00.000Z",
      () => 1791763200002.0,
    )
    is Some(original) else {
    fail("first preparation")
  }
  let binding = local_run_policy_binding(host, settings, crypto).unwrap()
  effect_finite_cli_ok(
    binding.accept_submitted_effect_values_run_policy(
      reference,
      preparation,
      original.request,
      original.allowed,
      original.definition,
      original.issued,
      "2026-10-12T00:00:00.000Z",
      1791763200003.0,
    ),
    "first.accept",
  )
  |> ignore
  let before = binding
    .lookup_submitted_run_policy(reference, original.request, 1791763200004.0)
    .unwrap()
  assert_true(
    local_effect_prepare_start_with_clocks(
      host,
      settings,
      crypto,
      preparation,
      reference,
      installed,
      scope,
      () => "not-a-time",
      () => 1791763200005.0,
    )
    is None,
  )
  let after = binding
    .lookup_submitted_run_policy(reference, original.request, 1791763200006.0)
    .unwrap()
  assert_eq(
    @run_host.client_local_run_policy_original_body(after),
    @run_host.client_local_run_policy_original_body(before),
  )
  effect_finite_cli_ok(host.close(), "host.close")
  effect_finite_cli_ok(sqlite.close_checked(), "sqlite.close")
}

///|
test "CLI Effect finite prefix refuses an accepted legacy missing Policy instead of recompiling it" {
  let (host, settings, crypto, installed, sqlite) = effect_finite_cli_host(
    "cli-effect-finite-missing",
  )
  defer {
    host.close() |> ignore
    sqlite.close_checked() |> ignore
  }
  let (reference, preparation, scope) = effect_finite_cli_submission(
    host, settings, crypto, "missing",
  )
  guard local_effect_prepare_start_with_clocks(
      host,
      settings,
      crypto,
      preparation,
      reference,
      installed,
      scope,
      () => "2026-10-12T00:00:00.000Z",
      () => 1791763200002.0,
    )
    is Some(original) else {
    fail("first preparation")
  }
  effect_finite_cli_ok(
    host.accept_submitted_effect_material_original(
      crypto,
      settings.principal,
      settings.connection,
      reference,
      preparation,
      original.request,
      original.allowed,
      original.definition,
      original.issued,
      1791763200003.0,
    ),
    "legacy.accept",
  )
  |> ignore
  let refused = try {
    local_effect_prepare_start_with_clocks(
      host,
      settings,
      crypto,
      preparation,
      reference,
      installed,
      scope,
      () => "2026-10-12T00:00:00.000Z",
      () => 1791763200004.0,
    )
    |> ignore
    None
  } catch {
    ClientStop(reason) => Some(reason)
  }
  assert_eq(refused, Some("LocalRunPolicyPreparationUnavailable"))
  effect_finite_cli_ok(host.close(), "host.close")
  effect_finite_cli_ok(sqlite.close_checked(), "sqlite.close")
}
