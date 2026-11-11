///|
let initial_reviewer_account : String =
  #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"current-machine-resolve","outcome":"allow","principal":{"any_of":["machine-user"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["resolve"]},"exclusions":[]}]}

///|
fn initial_reviewer_fixture(
  name : String,
  host_wire? : String = "{\"version\":\"actql-host/0.1\"}",
  account? : String = initial_reviewer_account,
  host_signing_subject? : (String, String, String)? = None,
) -> (NativeLocalHostConnection, String) {
  let top = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(top).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  let source = parent.open_child(name).unwrap()
  for (file, body) in [("account.json", account), ("host.json", host_wire)] {
    let writer = source.create_writer(file + ".stage", 65536L).unwrap()
    writer.append(@utf8.encode(body)).unwrap()
    writer.seal(file).unwrap() |> ignore
  }
  let path = top + "/" + name
  let crypto = @crypto.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let session = begin_native_local_host_adoption(
    path,
    "store",
    path,
    "account.json",
    "operator",
    crypto,
    configuration_files=["host.json"],
  ).unwrap()
  let material = session
    .create_initial_signing_material(crypto, host_signing_subject~)
    .unwrap()
  let host = session
    .open_journal_with_initial_signing_material(
      material,
      @host.client_local_default_signing_bootstrap_policy(),
      local_journal_test_library(),
      crypto,
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  (host, "host.json")
}

///|
test "initial Reviewer configuration projection never supplies the independent resolve outcome" {
  let (host, file) = initial_reviewer_fixture("initial-reviewer-data-not-allow")
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "machine-user", "cli", file)
    .unwrap()
  // These copied actor labels are metadata, not a new registration or Allow.
  // The same authenticated configuration remains physically current for both.
  let foreign = {
    ..installed,
    reviewer: {
      ..installed.reviewer,
      principal: "other-user",
      reviewer_id: "other-user",
    },
  }
  let configuration_only = installed.configuration_current() &&
    foreign.configuration_current()
  let role_is_fresh = installed.current() &&
    !foreign.current() &&
    installed.current()
  host.close().unwrap()
  assert_true(configuration_only && role_is_fresh)
  assert_false(installed.configuration_current())
  assert_false(foreign.current())
}

///|
test "initial Reviewer joins actual machine actor and initialized public key without granting Client read or issue" {
  let (host, file) = initial_reviewer_fixture("initial-reviewer-actor")
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "machine-user", "cli", file)
    .unwrap()
  let current = installed.current()
  let identity = installed.reviewer
  let public_cid = original.public_key().unwrap().cid()
  let read_denied = host.authorize({
      principal: "machine-user",
      connection: "cli",
      resource: "run",
      operation: "read",
    })
    is Ok(@authorization.Deny(_))
  let issue_denied = host.authorize({
      principal: "machine-user",
      connection: "cli",
      resource: "credential/" + original.issuer_identity().unwrap(),
      operation: "issue",
    })
    is Ok(@authorization.Deny(_))
  host.close().unwrap()
  assert_true(current)
  assert_eq(identity.principal, "machine-user")
  assert_eq(identity.reviewer_id, "machine-user")
  assert_eq(identity.key_id, public_cid)
  assert_true(read_denied && issue_denied)
  assert_false(installed.current())
}

///|
test "initial Reviewer rejects wrong actor connection named fallback and unadopted Host configuration" {
  let (host, file) = initial_reviewer_fixture("initial-reviewer-refusal")
  let original = host.restore_initial_signing_original().unwrap()
  let wrong_actor = host.install_initial_effect_reviewer(
      original, "other-user", "cli", file,
    )
    is Err(ReviewerUnavailable)
  let wrong_connection = host.install_initial_effect_reviewer(
      original, "machine-user", "other", file,
    )
    is Err(ReviewerUnavailable)
  let named = host.install_initial_effect_reviewer(
      original,
      "machine-user",
      "cli",
      file,
      signer_name=Some("missing"),
    )
    is Err(ReviewerUnavailable)
  let absent_file = host.install_initial_effect_reviewer(
      original, "machine-user", "cli", "not-adopted.json",
    )
    is Err(ReviewerUnavailable)
  host.close().unwrap()
  assert_true(wrong_actor && wrong_connection && named && absent_file)
}

///|
test "initial Reviewer does not override an explicit signer map or independent Account denial" {
  let (host, file) = initial_reviewer_fixture(
    "initial-reviewer-explicit",
    host_wire="{\"version\":\"actql-host/0.1\",\"signers\":{}}",
  )
  let explicit_map = host.install_initial_effect_reviewer(
      host.restore_initial_signing_original().unwrap(),
      "machine-user",
      "cli",
      file,
    )
    is Err(ReviewerUnavailable)
  host.close().unwrap()
  let (denied, denied_file) = initial_reviewer_fixture(
    "initial-reviewer-denied",
    account="{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[]}",
  )
  let denial = denied.install_initial_effect_reviewer(
      denied.restore_initial_signing_original().unwrap(),
      "machine-user",
      "cli",
      denied_file,
    )
    is Err(ReviewerUnavailable)
  denied.close().unwrap()
  assert_true(explicit_map && denial)
}

///|
test "initial Reviewer rejects another physical Host original and detects key generation replacement" {
  let (host, file) = initial_reviewer_fixture("initial-reviewer-own")
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "machine-user", "cli", file)
    .unwrap()
  let (foreign, foreign_file) = initial_reviewer_fixture(
    "initial-reviewer-foreign",
  )
  let foreign_rejected = foreign.install_initial_effect_reviewer(
      original, "machine-user", "cli", foreign_file,
    )
    is Err(ReviewerUnavailable)
  foreign.close().unwrap()
  // Same public metadata does not authenticate another original file generation.
  let root = host.session.root
  let (bytes, generation) = local_adoption_read(
    root, "local-signing-key.pem", 119L,
  ).unwrap()
  root.reclaim_generation("local-signing-key.pem", generation).unwrap()
  let writer = root.create_writer("replacement.stage", 119L).unwrap()
  writer.append(bytes).unwrap()
  writer.seal("local-signing-key.pem").unwrap() |> ignore
  let stale = !installed.current()
  host.close().unwrap()
  assert_true(foreign_rejected && stale)
}
