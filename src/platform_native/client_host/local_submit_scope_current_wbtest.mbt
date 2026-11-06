///|
// Actual original Session, Journal and Account diagnostics with explicitly
// selected legacy libraries; not an operational Read/SQL or business supplier.
fn submit_scope_current_capture(
  name : String,
  account : Bytes,
) -> NativeLocalJournalCapture raise {
  guard @authorization.admit_account_configuration_json(@utf8.decode(account))
    is Ok(_) else {
    fail("Scope fixture requires an admitted original Account before any I/O")
  }
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(base).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  parent.close().unwrap()
  let path = base + "/" + name
  let source = @filesystem.open_private_root(path).unwrap()
  let writer = source.create_writer("account.stage", 4096L).unwrap()
  writer.append(account).unwrap()
  writer.seal("account.json").unwrap() |> ignore
  source.close().unwrap()
  let crypto = epoch_test_crypto()
  let session = begin_native_local_host_adoption(
    path, "host", path, "account.json", "operator", crypto,
  ).unwrap()
  // Capture is existing-only. Initialize this fresh fixture through the actual
  // Journal Owner, close it, then restore its original durable installation.
  let seeded = session
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  seeded.close_owned_root_descriptors().unwrap()
  let existing = begin_existing_native_local_host_adoption_with_custody(
    path, "host", path, "account.json", "operator", crypto,
  ).unwrap()
  prepare_native_local_journal_capture(
    existing,
    local_journal_test_library(),
    crypto,
    100.0,
    8,
    8388608L,
  )
}

///|
test "Native submit scope identity stays exact without becoming Account permission" {
  let capture = submit_scope_current_capture(
    "submit-scope-current", policy_reuse_account_original,
  )
  assert_eq(capture.open().issue_family(), 0)
  let host = capture.original_host().unwrap()
  let material = host.adopted_current_material().unwrap()
  let body = @host.client_local_adopted_authority_scope_body(
    material,
    host.database,
    "operator",
    "cli",
  ).unwrap()
  let scope = local_adoption_digest(capture.crypto, body).unwrap()
  // This legacy component fixture cannot supply an installed physical Read.
  assert_true(
    capture.original_submit_allowed(host, material, "operator", "cli", scope)
    is Err(OriginalResourceScopePending),
  )
  let (request, _, _, _) = journal_test_run(
    "scope-current",
    "scope-run",
    scope~,
  )
  let authority = native_local_policy_authority_for(
    host,
    capture.crypto,
    "operator",
    "cli",
    request,
    SubmitOriginals,
  ).unwrap()
  assert_true(
    authority.current_with_material_for(host.journal, request, material),
  )
  let (changed_scope, _, _, _) = journal_test_run(
    "scope-changed",
    "scope-changed-run",
    scope="sha256:" + "0".repeat(64),
  )
  assert_false(
    authority.current_with_material_for(host.journal, changed_scope, material),
  )
  assert_true(
    native_local_policy_authority_for(
      host,
      capture.crypto,
      "operator",
      "cli",
      changed_scope,
      SubmitOriginals,
    )
    is Err(AuthorizationDenied),
  )
  let other_scope = local_adoption_digest(
    capture.crypto,
    @host.client_local_adopted_authority_scope_body(
      material,
      host.database,
      "operator",
      "other",
    ).unwrap(),
  ).unwrap()
  let (other_request, _, _, _) = journal_test_run(
    "scope-other",
    "scope-other-run",
    scope=other_scope,
  )
  assert_true(
    native_local_policy_authority_for(
      host,
      capture.crypto,
      "operator",
      "other",
      other_request,
      SubmitOriginals,
    )
    is Err(AuthorizationDenied),
  )
  assert_false(
    native_local_policy_account_allowed(
      material,
      host.database,
      "operator",
      "other",
      SubmitOriginals,
    ),
  )
  let foreign = submit_scope_current_capture(
    "submit-scope-foreign", policy_reuse_account_original,
  )
  assert_eq(foreign.open().issue_family(), 0)
  let foreign_host = foreign.original_host().unwrap()
  let foreign_material = foreign_host.adopted_current_material().unwrap()
  assert_false(
    authority.current_with_material_for(host.journal, request, foreign_material),
  )
  assert_true(
    @host.client_local_adopted_authority_scope_body(
      foreign_material,
      host.database,
      "operator",
      "cli",
    ).map_err(local_current_material_issue)
    is Err(CustodyLost),
  )
  assert_eq(foreign.close().issue_family(), 0)
  assert_eq(capture.close().issue_family(), 0)
  assert_false(
    authority.current_with_material_for(host.journal, request, material),
  )
  assert_true(
    @host.client_local_adopted_authority_scope_body(
      material,
      host.database,
      "operator",
      "cli",
    ).map_err(local_current_material_issue)
    is Err(Closed),
  )
}

///|
test "Native submit scope DATA never overrides Deny or changed original custody" {
  let conflicting : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"allow\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"submit\"]},\"exclusions\":[]},{\"entry_id\":\"deny\",\"outcome\":\"deny\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"submit\"]},\"exclusions\":[]}]}"
  assert_true(
    @authorization.admit_account_configuration_json(@utf8.decode(conflicting))
    is Err(@authorization.ConflictingOutcomes(_)),
  )
  let denied : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"deny\",\"outcome\":\"deny\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"submit\"]},\"exclusions\":[]}]}"
  let capture = submit_scope_current_capture("submit-scope-denied", denied)
  assert_eq(capture.open().issue_family(), 0)
  let host = capture.original_host().unwrap()
  let material = host.adopted_current_material().unwrap()
  let body = @host.client_local_adopted_authority_scope_body(
    material,
    host.database,
    "operator",
    "cli",
  ).unwrap()
  let scope = local_adoption_digest(capture.crypto, body).unwrap()
  assert_true(
    capture.original_submit_allowed(host, material, "operator", "cli", scope)
    is Err(OriginalResourceScopePending),
  )
  let (request, _, _, _) = journal_test_run(
    "scope-denied",
    "scope-denied-run",
    scope~,
  )
  assert_true(
    native_local_policy_authority_for(
      host,
      capture.crypto,
      "operator",
      "cli",
      request,
      SubmitOriginals,
    )
    is Err(AuthorizationDenied),
  )
  assert_false(
    native_local_policy_account_allowed(
      material,
      host.database,
      "operator",
      "cli",
      SubmitOriginals,
    ),
  )
  let source = host.session.source_root
  source
  .reclaim_generation(host.session.source_name, host.session.source_generation)
  .unwrap()
  let replacement = source.create_writer("replacement.stage", 4096L).unwrap()
  replacement.append(denied).unwrap()
  replacement.seal(host.session.source_name).unwrap() |> ignore
  assert_true(
    @host.client_local_adopted_authority_scope_body(
      material,
      host.database,
      "operator",
      "cli",
    ).map_err(local_current_material_issue)
    is Err(SourceChanged),
  )
  assert_true(
    host.authority_scope_cid("operator", "cli", capture.crypto)
    is Err(SourceChanged),
  )
  assert_eq(capture.close().issue_family(), 0)
}
