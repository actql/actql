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
// load_library uses the existing legacy ARC finalizer. Library.close_checked
// belongs only to selected components; the Host still requires its DB/session ACK.
fn effect_finite_cli_host(
  name : String,
  ttl_ms? : Double = 100.0,
  observed_at? : String = "2026-10-10T00:00:00.000Z",
  managed_root? : Bool = false,
) -> (
  @local_host.NativeLocalHostConnection,
  LocalHostSettings,
  @local_crypto.Library,
  LocalRunInstallation,
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
      observed_at,
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
        managed_root_path=if managed_root { Some(root) } else { None },
      ),
      "adoption",
    ).open_journal(sqlite, crypto, ttl_ms, 8, 8388608L),
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
    ttl_ms,
    record_limit: 8,
    snapshot_bytes: 8388608L,
    installation_files: names,
    source_file: None,
    run_file: Some("run.json"),
    read_file: Some("read.json"),
    run_policy_profile_file: Some("profile.json"),
    reviewer_file: None,
    initial_host_signing: None,
  }
  let wire = @utf8.decode(
    originals.iter().find_first(pair => pair.0 == "run.json").unwrap().1,
  ) catch {
    _ => fail("run.utf8")
  }
  (host, settings, crypto, local_run_installation(wire))
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
test "CLI Effect preflight refuses its supplier while actual Policy values remain fresh and unaccepted" {
  let (host, settings, crypto, installed) = effect_finite_cli_host(
    "cli-effect-finite-fresh",
  )
  defer host.close() |> ignore
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
  guard prepared is AuthoritySupplierUnavailable else {
    fail("expected completed preflight")
  }
  // Observe values through the actual Policy/compilation Owners, not through
  // an uninstalled CLI supplier carrier. Preflight above remains a refusal.
  let request = local_effect_request_identity(
    preparation,
    scope,
    @local_host.native_client_submission_request_id(reference),
  )
  let binding = local_run_policy_binding(host, settings, crypto).unwrap()
  guard binding.prepare_submission_policy(
      reference, preparation, request, "2026-10-12T00:00:00.000Z", 1791763200002.0,
    )
    is Ok(Pending(retention, issued_at)) else {
    fail("actual policy preparation")
  }
  let retention_fields = @decode.open_object(
    local_input_cursor(@publication.publication_contract_json(retention)),
  ).unwrap()
  let original = local_effect_first_compilation(
    preparation,
    scope,
    host.configuration().unwrap().configuration_cid(),
    installed.namespace_id,
    @local_host.native_client_submission_request_id(reference),
    issued_at,
    run_text(retention_fields, "available_until"),
  )

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
}

///|
test "CLI Effect finite prefix selects an accepted original before an invalid candidate time" {
  let (host, settings, crypto, installed) = effect_finite_cli_host(
    "cli-effect-finite-accepted",
  )
  defer host.close() |> ignore
  let (reference, preparation, scope) = effect_finite_cli_submission(
    host, settings, crypto, "accepted",
  )
  // Accept this preparation's first compilation before testing that lookup
  // wins over an invalid replacement time in the later preflight call.
  let request = local_effect_request_identity(
    preparation,
    scope,
    @local_host.native_client_submission_request_id(reference),
  )
  let binding = local_run_policy_binding(host, settings, crypto).unwrap()
  guard binding.prepare_submission_policy(
      reference, preparation, request, "2026-10-12T00:00:00.000Z", 1791763200002.0,
    )
    is Ok(Pending(retention, issued_at)) else {
    fail("actual policy preparation")
  }
  let retention_fields = @decode.open_object(
    local_input_cursor(@publication.publication_contract_json(retention)),
  ).unwrap()
  let original = local_effect_first_compilation(
    preparation,
    scope,
    host.configuration().unwrap().configuration_cid(),
    installed.namespace_id,
    @local_host.native_client_submission_request_id(reference),
    issued_at,
    run_text(retention_fields, "available_until"),
  )

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
    is AlreadyAccepted,
  )
  let after = binding
    .lookup_submitted_run_policy(reference, original.request, 1791763200006.0)
    .unwrap()
  assert_eq(
    @run_host.client_local_run_policy_original_body(after),
    @run_host.client_local_run_policy_original_body(before),
  )
  effect_finite_cli_ok(host.close(), "host.close")
}

///|
test "CLI Effect finite prefix refuses an accepted legacy missing Policy instead of recompiling it" {
  let (host, settings, crypto, installed) = effect_finite_cli_host(
    "cli-effect-finite-missing",
  )
  defer host.close() |> ignore
  let (reference, preparation, scope) = effect_finite_cli_submission(
    host, settings, crypto, "missing",
  )
  // Retain the first compilation as legacy material without a Policy record;
  // the later preflight must refuse it instead of issuing another compilation.
  let request = local_effect_request_identity(
    preparation,
    scope,
    @local_host.native_client_submission_request_id(reference),
  )
  let binding = local_run_policy_binding(host, settings, crypto).unwrap()
  guard binding.prepare_submission_policy(
      reference, preparation, request, "2026-10-12T00:00:00.000Z", 1791763200002.0,
    )
    is Ok(Pending(retention, issued_at)) else {
    fail("actual policy preparation")
  }
  let retention_fields = @decode.open_object(
    local_input_cursor(@publication.publication_contract_json(retention)),
  ).unwrap()
  let original = local_effect_first_compilation(
    preparation,
    scope,
    host.configuration().unwrap().configuration_cid(),
    installed.namespace_id,
    @local_host.native_client_submission_request_id(reference),
    issued_at,
    run_text(retention_fields, "available_until"),
  )

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
}

///|
test "actual Policy binding accepts finite retention with the same original compilation materials" {
  let (host, settings, crypto, installed) = effect_finite_cli_host(
    "cli-effect-selected-accept",
  )
  defer host.close() |> ignore
  let (reference, preparation, scope) = effect_finite_cli_submission(
    host, settings, crypto, "selected-accept",
  )
  // The separate preflight case preserves its supplier refusal. This Policy
  // case compiles once: preflight would retain a different live compilation
  // on the same preparation before the original material binding below.
  let request = local_effect_request_identity(
    preparation,
    scope,
    @local_host.native_client_submission_request_id(reference),
  )
  let binding = local_run_policy_binding(host, settings, crypto).unwrap()
  guard binding.prepare_submission_policy(
      reference, preparation, request, "2026-10-12T00:00:00.000Z", 1791763200002.0,
    )
    is Ok(Pending(retention, issued_at)) else {
    fail("actual policy preparation")
  }
  let retention_fields = @decode.open_object(
    local_input_cursor(@publication.publication_contract_json(retention)),
  ).unwrap()
  let original = local_effect_first_compilation(
    preparation,
    scope,
    host.configuration().unwrap().configuration_cid(),
    installed.namespace_id,
    @local_host.native_client_submission_request_id(reference),
    issued_at,
    run_text(retention_fields, "available_until"),
  )
  let materials = @run_host.bind_prepared_client_effect_original_materials(
    original.allowed,
    original.definition,
    original.issued,
    request=Some(original.request),
  ).unwrap()

  assert_eq(issued_at, "2026-10-12T00:00:00.000Z")
  assert_eq(
    @publication.result_retention_interval_state(
      retention, "2026-10-12T00:00:00.000Z",
    ),
    Ok("available"),
  )
  assert_eq(
    @publication.result_retention_interval_state(
      installed.retention,
      "2026-10-12T00:00:00.000Z",
    ),
    Ok("delete_due"),
  )
  let accepted = effect_finite_cli_ok(
    binding.accept_submitted_effect_values_run_policy(
      reference,
      preparation,
      original.request,
      original.allowed,
      original.definition,
      original.issued,
      issued_at,
      1791763200003.0,
    ),
    "selected.accept",
  )
  let saved = effect_finite_cli_ok(
    binding.lookup_submitted_run_policy(
      reference,
      original.request,
      1791763200004.0,
    ),
    "selected.policy",
  )
  assert_eq(
    @run_host.client_local_run_policy_original_issued_at(saved),
    "2026-10-12T00:00:00.000Z",
  )
  assert_eq(
    @run_host.client_local_run_policy_original_read_expires_at(saved),
    "2026-10-13T00:00:00.000Z",
  )
  assert_eq(
    @publication.publication_contract_json(
      @run_host.client_local_run_policy_original_retention(saved),
    ),
    @publication.publication_contract_json(retention),
  )
  let packet = effect_finite_cli_ok(
    host.lookup_submitted_effect_material_original(
      crypto,
      settings.principal,
      settings.connection,
      reference,
      original.request,
      1791763200005.0,
    ),
    "selected.packet",
  )
  assert_eq(
    @local_host.native_client_retained_effect_materials_cid(packet),
    @run_host.client_effect_normalization_materials_cid(materials).unwrap(),
  )
  assert_eq(
    @publication.publication_contract_identity(
      @local_host.native_client_retained_effect_materials_run(packet),
    ),
    @publication.publication_contract_identity(original.definition),
  )
  let result_policy = effect_finite_cli_ok(
    host.lookup_submitted_effect_values_policy_original(
      crypto,
      settings.principal,
      settings.connection,
      reference,
      original.request,
      1791763200006.0,
    ),
    "selected.result-policy",
  )
  let expected = installed.source_free.unwrap()
  assert_eq(
    @publication.captured_effect_dependency_body_cid(result_policy),
    expected.result_policy_cid,
  )
  assert_eq(
    @publication.captured_effect_dependency_body_json(result_policy),
    expected.result_policy_wire,
  )
  assert_true(
    @local_host.native_client_submitted_run_admission(accepted) is Some(_),
  )
  effect_finite_cli_ok(host.close(), "selected.host.close")
}

///|
test "actual Policy binding reconciles the same original across lost acknowledgement and reopen" {
  let name = "cli-effect-selected-reopen"
  let (host, settings, crypto, installed) = effect_finite_cli_host(name)
  defer host.close() |> ignore
  let (reference, preparation, scope) = effect_finite_cli_submission(
    host, settings, crypto, "selected-reopen",
  )
  // Exercise acceptance and ACK-loss recovery with the first compilation of
  // this preparation; the separate preflight case retains its own refusal.
  let request = local_effect_request_identity(
    preparation,
    scope,
    @local_host.native_client_submission_request_id(reference),
  )
  let binding = local_run_policy_binding(host, settings, crypto).unwrap()
  guard binding.prepare_submission_policy(
      reference, preparation, request, "2026-10-12T00:00:00.000Z", 1791763200002.0,
    )
    is Ok(Pending(retention, issued_at)) else {
    fail("actual policy preparation")
  }
  let retention_fields = @decode.open_object(
    local_input_cursor(@publication.publication_contract_json(retention)),
  ).unwrap()
  let original = local_effect_first_compilation(
    preparation,
    scope,
    host.configuration().unwrap().configuration_cid(),
    installed.namespace_id,
    @local_host.native_client_submission_request_id(reference),
    issued_at,
    run_text(retention_fields, "available_until"),
  )

  // The acceptance response is deliberately withheld from the caller model.
  // This is ACK-loss simulation, not a claim about a physical transport fault.
  effect_finite_cli_ok(
    binding.accept_submitted_effect_values_run_policy(
      reference,
      preparation,
      original.request,
      original.allowed,
      original.definition,
      original.issued,
      issued_at,
      1791763200003.0,
    ),
    "reopen.accept",
  )
  |> ignore
  let saved = effect_finite_cli_ok(
    binding.lookup_submitted_run_policy(
      reference,
      original.request,
      1791763200004.0,
    ),
    "reopen.lookup",
  )
  let body = @run_host.client_local_run_policy_original_body(saved)
  let before = effect_finite_cli_ok(host.run_journal(), "reopen.journal")
    .lookup(original.request, true)
    .unwrap()
  guard before is Retained(before_record) else { fail("reopen.before") }
  // Accepted lookup must win before any replacement candidate time is parsed.
  let stale_issued_at = "not-a-time"
  effect_finite_cli_ok(
    binding.accept_submitted_effect_values_run_policy(
      reference,
      preparation,
      original.request,
      original.allowed,
      original.definition,
      original.issued,
      stale_issued_at,
      1791763200005.0,
    ),
    "reopen.same-accept",
  )
  |> ignore
  assert_eq(
    @run_host.client_local_run_policy_original_body(
      binding
      .lookup_submitted_run_policy(reference, original.request, 1791763200006.0)
      .unwrap(),
    ),
    body,
  )
  let foreign_preparation = local_effect_prefix_fixture_preparation()
  assert_true(
    binding.accept_submitted_effect_values_run_policy(
      reference,
      foreign_preparation,
      original.request,
      original.allowed,
      original.definition,
      original.issued,
      issued_at,
      1791763200007.0,
    )
    is Err(@local_host.ForeignPreparation),
  )
  effect_finite_cli_ok(host.close(), "reopen.host.close")
  let sqlite = effect_finite_cli_ok(
    @local_sqlite.load_library(
      @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    ),
    "reopen.sqlite",
  )
  let reopened = effect_finite_cli_ok(
    effect_finite_cli_ok(
      @local_host.begin_native_local_host_adoption(
        settings.state_parent,
        settings.state_name,
        settings.managed_root,
        settings.account_file,
        settings.account_id,
        crypto,
        existing_only=true,
        configuration_files=settings.installation_files,
      ),
      "reopen.adoption",
    ).open_journal(
      sqlite,
      crypto,
      settings.ttl_ms,
      settings.record_limit,
      settings.snapshot_bytes,
    ),
    "reopen.open",
  )
  defer reopened.close() |> ignore
  let restored = local_run_policy_binding(reopened, settings, crypto)
    .unwrap()
    .lookup_submitted_run_policy(reference, original.request, 1791763200008.0)
    .unwrap()
  assert_eq(@run_host.client_local_run_policy_original_body(restored), body)
  guard reopened.run_journal().unwrap().lookup(original.request, true)
    is Ok(Retained(after_record)) else {
    fail("reopen.after")
  }
  assert_eq(
    @local_host.native_client_run_record_revision(after_record),
    @local_host.native_client_run_record_revision(before_record),
  )
  assert_eq(
    @publication.publication_contract_identity(
      @local_host.native_client_run_definition(after_record),
    ),
    @publication.publication_contract_identity(original.definition),
  )
  effect_finite_cli_ok(reopened.close(), "reopen.close")
}
