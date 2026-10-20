///|
// Actual original Session, Journal and Account diagnostics with explicitly
// selected legacy libraries; not an operational Read/SQL or business supplier.
fn submit_scope_current_capture(
  name : String,
  account : Bytes,
) -> NativeLocalJournalCapture {
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
  prepare_native_local_journal_capture(
    session,
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
  assert_true(
    capture.original_submit_allowed(host, material, "operator", "cli", scope)
    is Ok(true),
  )
  assert_true(
    capture.original_submit_allowed(
      host,
      material,
      "operator",
      "cli",
      "sha256:" + "0".repeat(64),
    )
    is Err(Epoch(ScopeMismatch)),
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
  assert_true(
    capture.original_submit_allowed(
      host, material, "operator", "other", other_scope,
    )
    is Ok(false),
  )
  let foreign = submit_scope_current_capture(
    "submit-scope-foreign", policy_reuse_account_original,
  )
  assert_eq(foreign.open().issue_family(), 0)
  let foreign_host = foreign.original_host().unwrap()
  let foreign_material = foreign_host.adopted_current_material().unwrap()
  assert_true(
    capture.original_submit_allowed(
      host, foreign_material, "operator", "cli", scope,
    )
    is Err(CustodyLost),
  )
  assert_eq(foreign.close().issue_family(), 0)
  assert_eq(capture.close().issue_family(), 0)
  assert_true(
    capture.original_submit_allowed(host, material, "operator", "cli", scope)
    is Err(Closed),
  )
}

///|
test "Native submit scope DATA never overrides Deny or changed original custody" {
  let denied : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"allow\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"submit\"]},\"exclusions\":[]},{\"entry_id\":\"deny\",\"outcome\":\"deny\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"submit\"]},\"exclusions\":[]}]}"
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
    is Ok(false),
  )
  let source = host.session.source_root
  source
  .reclaim_generation(host.session.source_name, host.session.source_generation)
  .unwrap()
  let replacement = source.create_writer("replacement.stage", 4096L).unwrap()
  replacement.append(denied).unwrap()
  replacement.seal(host.session.source_name).unwrap() |> ignore
  assert_true(
    capture.original_submit_allowed(host, material, "operator", "cli", scope)
    is Err(SourceChanged),
  )
  assert_eq(capture.close().issue_family(), 0)
}
