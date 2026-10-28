///|
fn initial_signing_cli_options(
  initialize_signing : Bool,
) -> LocalInitialSigningAdoptionOptions {
  {
    initialize_signing,
    ttl_ms: 100.0,
    max_records: 8,
    max_snapshot_bytes: 8388608L,
    initial_host_signing: None,
  }
}

///|
fn initial_signing_cli_session(
  name : String,
  existing_only? : Bool = false,
) -> (
  @local_host.NativeLocalAdoptionSession,
  @local_crypto.Library,
  @local_sqlite.Library,
) {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let files = @local_filesystem.open_private_root(path).unwrap()
  if !existing_only {
    files.create_directory(name + ".parent").unwrap() |> ignore
    let writer = files.create_writer(name + ".account.stage", 8192L).unwrap()
    writer
    .append(
      b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[]}",
    )
    .unwrap()
    writer.seal(name + ".account.json").unwrap() |> ignore
  }
  files.close().unwrap()
  let crypto = @local_crypto.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(64),
  ).unwrap()
  let sqlite = @local_sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let session = @local_host.begin_native_local_host_adoption(
    path + "/" + name + ".parent",
    name + ".host",
    path,
    name + ".account.json",
    "operator",
    crypto,
    existing_only~,
  ).unwrap()
  (session, crypto, sqlite)
}

///|
test "CLI initial signing selection is explicit and confined to adoption" {
  let selected = command().parse(
    argv=["--mode", "local", "adopt", "--initialize-signing"],
    env=Map([]),
  )
  guard selected.subcommand is Some(("adopt", child)) else {
    fail("missing original adopt command")
  }
  assert_true(child.flags.get("initialize-signing").unwrap_or(false))
  let ordinary = command().parse(argv=["--mode", "local", "adopt"], env=Map([]))
  guard ordinary.subcommand is Some(("adopt", child)) else {
    fail("missing ordinary adopt command")
  }
  assert_false(child.flags.get("initialize-signing").unwrap_or(false))
  for operation in ["connect", "status"] {
    let rejected = try {
      command().parse(
        argv=["--mode", "local", operation, "--initialize-signing"],
        env=Map([]),
      )
      |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "CLI explicit initial signing adopts the original key and policy without Account permissions" {
  let (session, crypto, sqlite) = initial_signing_cli_session("cli-initial-key")
  let intent = session.intent_cid()
  let host = local_open_initial_signing_adoption(
    session,
    sqlite,
    crypto,
    initial_signing_cli_options(true),
  ).unwrap()
  let original = host.restore_initial_signing_original().unwrap()
  assert_eq(original.issuer_identity().unwrap(), "local-signing/" + intent)
  assert_eq(original.policy().unwrap().max_uses(), 1)
  assert_true(original.require_current() is Ok(_))
  // Material custody supplies no Run or key/issue permission.
  assert_false(
    host.authorize({
      principal: "operator",
      connection: "cli",
      resource: "run",
      operation: "resolve",
    })
    is Ok(@authorization.Allow(_)),
  )
  host.close().unwrap()
  assert_true(original.require_current() is Err(_))
}

///|
test "CLI ordinary legacy adoption cannot initialize a missing signing original on cold reopen" {
  let name = "cli-initial-legacy"
  let (session, crypto, sqlite) = initial_signing_cli_session(name)
  let host = local_open_initial_signing_adoption(
    session,
    sqlite,
    crypto,
    initial_signing_cli_options(false),
  ).unwrap()
  assert_true(host.restore_initial_signing_original() is Err(_))
  host.close().unwrap()
  let (cold, crypto, sqlite) = initial_signing_cli_session(
    name,
    existing_only=true,
  )
  assert_true(
    local_open_initial_signing_adoption(
      cold,
      sqlite,
      crypto,
      initial_signing_cli_options(true),
    )
    is Err(_),
  )
  assert_true(cold.close())
  let (cold, crypto, sqlite) = initial_signing_cli_session(
    name,
    existing_only=true,
  )
  let reopened = local_open_initial_signing_adoption(
    cold,
    sqlite,
    crypto,
    initial_signing_cli_options(false),
  ).unwrap()
  assert_true(reopened.restore_initial_signing_original() is Err(_))
  reopened.close().unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = @local_filesystem.open_private_root(
    path + "/" + name + ".parent/" + name + ".host",
  ).unwrap()
  assert_true(root.inspect_generation("local-signing-key.pem").unwrap() is None)
  root.close().unwrap()
}

///|
test "CLI cold ordinary reopen restores the same initial public original without another creation" {
  let name = "cli-initial-reopen"
  let (session, crypto, sqlite) = initial_signing_cli_session(name)
  let host = local_open_initial_signing_adoption(
    session,
    sqlite,
    crypto,
    initial_signing_cli_options(true),
  ).unwrap()
  let original = host.restore_initial_signing_original().unwrap()
  let issuer = original.issuer_identity().unwrap()
  let public_key = original.public_key().unwrap().cid()
  host.close().unwrap()
  let (cold, crypto, sqlite) = initial_signing_cli_session(
    name,
    existing_only=true,
  )
  let host = local_open_initial_signing_adoption(
    cold,
    sqlite,
    crypto,
    initial_signing_cli_options(false),
  ).unwrap()
  let restored = host.restore_initial_signing_original().unwrap()
  assert_eq(restored.issuer_identity().unwrap(), issuer)
  assert_eq(restored.public_key().unwrap().cid(), public_key)
  host.close().unwrap()
}
